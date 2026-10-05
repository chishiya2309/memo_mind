const crypto = require('node:crypto');
const { canonical, fail } = require('../backup/validation');
const { key, parents } = require('./schema');
const { mergeOperations } = require('./merge');
class FirestoreSyncStore {
  constructor(db) { this.db = db; }
  root(uid) { return this.db.collection('users').doc(uid).collection('sync').doc('library'); }
  async status(uid) { return (await this.root(uid).get()).data() || { initialized: false, revision: 0 }; }
  async initialize(uid, sourceId) {
    return this.db.runTransaction(async tx => {
      const ref = this.root(uid), current = (await tx.get(ref)).data();
      if (current?.initialized) return current;
      const state = { initialized: true, revision: current?.revision || 0, sourceId, initializedAt: Date.now() };
      tx.set(ref, state); return state;
    });
  }
  async push(uid, groupId, deviceId, operations, resolveConflictId, restore = false) {
    if(new Set(operations.map(op=>op.operationId)).size!==operations.length)fail('invalid_sync','Mã thay đổi bị trùng.',400);
    const root = this.root(uid), digest = crypto.createHash('sha256').update(canonical({ deviceId, operations, resolveConflictId: resolveConflictId || null, restore })).digest('hex');
    return this.db.runTransaction(async tx => {
      const receiptRef = root.collection('receipts').doc(groupId);
      const [stateSnap, receiptSnap] = await Promise.all([tx.get(root), tx.get(receiptRef)]);
      const prior = receiptSnap.data();
      if (prior) { if (prior.digest !== digest) fail('operation_conflict', 'Mã thao tác đã dùng cho dữ liệu khác.', 409); return prior.result; }
      const state = stateSnap.data();
      if (!state?.initialized) fail('migration_required', 'Cần chọn dữ liệu ban đầu.', 409);
      const refs = [...new Set(operations.flatMap(op => [key(op.table, op.entityId), ...parents(op.table, op.data)]))].map(k => root.collection('entities').doc(k));
      const snapshots = await Promise.all(refs.map(ref => tx.get(ref)));
      const entities = new Map(snapshots.filter(s => s.exists).map(s => [s.id, s.data()]));
      const opRefs = operations.map(op => root.collection('operations').doc(op.operationId));
      const opSnapshots = await Promise.all(opRefs.map(ref=>tx.get(ref)));
      const pending = [], oldReceipts = [];
      const opDigests = operations.map(op=>crypto.createHash('sha256').update(canonical({op,deviceId,restore,resolveConflictId:resolveConflictId||null})).digest('hex'));
      operations.forEach((op,i)=>{
        const old = opSnapshots[i].data();
        if (old && old.digest!==opDigests[i]) fail('operation_conflict','Mã thay đổi đã được dùng.',409);
        if(old)oldReceipts.push(old.receipt);else pending.push(op);
      });
      let conflictRef;
      if (resolveConflictId) {
        conflictRef = root.collection('conflicts').doc(resolveConflictId);
        const conflict = (await tx.get(conflictRef)).data();
        if (!conflict || conflict.status !== 'open' || operations.length !== 1 || conflict.table !== operations[0].table || conflict.entityId !== operations[0].entityId || entities.get(key(conflict.table, conflict.entityId))?.version !== operations[0].baseVersion) fail('conflict_changed', 'Dữ liệu đã thay đổi. Hãy tải lại xung đột.', 409);
      }
      const merged = mergeOperations(entities, pending, { revision: state.revision, deviceId, resolveConflictId, restore });
      for (const change of merged.changes) {
        tx.set(root.collection('entities').doc(key(change.table, change.entityId)), change);
        tx.set(root.collection('changes').doc(String(change.version).padStart(16, '0')), { ...change, groupId, groupEnd: change === merged.changes.at(-1) });
      }
      for (const c of merged.conflicts) tx.set(root.collection('conflicts').doc(c.conflictId), c);
      if (conflictRef) tx.update(conflictRef, { status: 'resolved', resolvedAt: Date.now() });
      merged.receipts.forEach(receipt=>{
        const index=operations.findIndex(op=>op.operationId===receipt.operationId);
        tx.set(opRefs[index],{digest:opDigests[index],receipt});
      });
      const result = { receipts: [...oldReceipts,...merged.receipts], revision: merged.revision };
      tx.set(root, { ...state, revision: merged.revision, updatedAt: Date.now() });
      tx.set(receiptRef, { digest, result }); return result;
    });
  }
  async stage(uid, body) {
    const ref = this.root(uid).collection('staging').doc(`${body.groupId}-${body.partIndex}`);
    const digest = crypto.createHash('sha256').update(canonical(body)).digest('hex');
    await this.db.runTransaction(async tx => {
      const prior = (await tx.get(ref)).data();
      if (prior && prior.digest !== digest) fail('operation_conflict', 'Phần dữ liệu đã được dùng.', 409);
      if (!prior) tx.set(ref, { ...body, digest, createdAt: Date.now() });
    });
    return { staged: true };
  }
  async commit(uid, groupId) {
    const parts = (await this.root(uid).collection('staging').where('groupId','==',groupId).get()).docs.map(d=>d.data()).sort((a,b)=>a.partIndex-b.partIndex);
    if (!parts.length || parts.length !== parts[0].partsCount || parts.some((p,i)=>p.partIndex!==i || p.deviceId!==parts[0].deviceId || p.partsCount!==parts.length || p.restore!==parts[0].restore)) fail('incomplete_group', 'Nhóm dữ liệu chưa tải đủ.', 409);
    const operations = parts.flatMap(p=>p.operations);
    if (Buffer.byteLength(JSON.stringify(operations)) > 3 * 1024 * 1024) fail('sync_limit', 'Nhóm dữ liệu quá lớn.', 413);
    return this.push(uid,groupId,parts[0].deviceId,operations,undefined,parts[0].restore);
  }
  async changes(uid, cursor, limit) {
    const result = await this.root(uid).collection('changes').where('version', '>', cursor).orderBy('version').limit(limit).get();
    let changes = result.docs.map(d => d.data());
    // Clients never receive half of an atomic group at the normal 100-row page size.
    if (changes.length === limit && !changes.at(-1).groupEnd) {
      const end = changes.findLastIndex(c => c.groupEnd);
      if (end >= 0) changes = changes.slice(0, end + 1);
    }
    return { changes, cursor: changes.at(-1)?.version || cursor, hasMore: result.docs.length === limit };
  }
  async conflicts(uid) {
    const values = (await this.root(uid).collection('conflicts').where('status', '==', 'open').get()).docs.map(d => d.data());
    return Promise.all(values.map(async c => {
      const current = (await this.root(uid).collection('entities').doc(key(c.table,c.entityId)).get()).data();
      return current ? { ...c, version: current.version, remote: { data: current.data, deleted: current.deleted, deviceId: current.deviceId } } : c;
    }));
  }
  async file(uid, hash) { return (await this.root(uid).collection('files').doc(hash).get()).data(); }
  async saveFile(uid, hash, data) { await this.root(uid).collection('files').doc(hash).set(data); }
}
function configuredSyncAdapters() {
  const backup = require('../backup/adapters').configuredAdapters();
  if (!backup) return null;
  return { verifyToken: backup.verifyToken, objects: backup.objects, store: new FirestoreSyncStore(backup.metadata.db) };
}
module.exports = { FirestoreSyncStore, configuredSyncAdapters };
