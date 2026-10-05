const crypto = require('node:crypto');
const { mergeOperations } = require('../src/sync/merge');
const { canonical, fail } = require('../src/backup/validation');
class MemorySyncStore {
  staged = new Map();
  users = new Map(); tail = Promise.resolve();
  user(uid) { if (!this.users.has(uid)) this.users.set(uid, { initialized: false, revision: 0, entities: new Map(), changes: [], conflicts: new Map(), receipts: new Map(), opReceipts: new Map(), files: new Map() }); return this.users.get(uid); }
  async status(uid) { const u = this.user(uid); return { initialized: u.initialized, revision: u.revision }; }
  async initialize(uid, sourceId) { const u = this.user(uid); u.initialized = true; u.sourceId ||= sourceId; return this.status(uid); }
  async stage(uid, body) { const key=`${uid}/${body.groupId}/${body.partIndex}`, prior=this.staged.get(key);if(prior&&canonical(prior)!==canonical(body))fail('operation_conflict','Part changed',409);this.staged.set(key,structuredClone(body));return {staged:true}; }
  async commit(uid, groupId) {const first=this.staged.get(`${uid}/${groupId}/0`);if(!first)fail('incomplete_group','Missing group',409);const parts=Array.from({length:first.partsCount},(_,i)=>this.staged.get(`${uid}/${groupId}/${i}`));if(parts.some(p=>!p))fail('incomplete_group','Missing part',409);return this.push(uid,groupId,first.deviceId,parts.flatMap(p=>p.operations),undefined,first.restore);}
  async push(uid, groupId, deviceId, operations, resolveConflictId, restore = false) {
    const result = this.tail.then(() => {
      const u = this.user(uid);
      if (!u.initialized) fail('migration_required', 'Cần chọn thư viện.', 409);
      const digest = crypto.createHash('sha256').update(canonical({ deviceId, operations, resolveConflictId: resolveConflictId || null, restore })).digest('hex');
      const prior = u.receipts.get(groupId);
      if (prior) { if (prior.digest !== digest) fail('operation_conflict', 'Mã thao tác đã dùng.', 409); return structuredClone(prior.result); }
      if (resolveConflictId) {
        const c = u.conflicts.get(resolveConflictId), op = operations[0];
        if (!c || c.status !== 'open' || operations.length !== 1 || c.table !== op.table || c.entityId !== op.entityId || u.entities.get(`${c.table}:${c.entityId}`)?.version !== op.baseVersion) fail('conflict_changed', 'Dữ liệu thay đổi.', 409);
      }
      const pending=[],oldReceipts=[];
      for(const op of operations){const old=u.opReceipts.get(op.operationId),digest=canonical({op,deviceId,restore,resolveConflictId:resolveConflictId||null});if(old&&old.digest!==digest)fail('operation_conflict','Mã thao tác đã dùng.',409);if(old)oldReceipts.push(old.receipt);else pending.push(op);}
      const merged = mergeOperations(u.entities, pending, { revision: u.revision, deviceId, resolveConflictId, restore });
      u.entities = merged.entities; u.revision = merged.revision;
      u.changes.push(...merged.changes.map((c, i) => ({ ...structuredClone(c), groupId, groupEnd: i === merged.changes.length - 1 })));
      merged.conflicts.forEach(c => u.conflicts.set(c.conflictId, c));
      if (resolveConflictId) u.conflicts.get(resolveConflictId).status = 'resolved';
      for(const receipt of merged.receipts){const op=operations.find(o=>o.operationId===receipt.operationId);u.opReceipts.set(op.operationId,{digest:canonical({op,deviceId,restore,resolveConflictId:resolveConflictId||null}),receipt});}
      const response = { receipts: [...oldReceipts,...merged.receipts], revision: merged.revision };
      u.receipts.set(groupId, { digest, result: response }); return structuredClone(response);
    });
    this.tail = result.catch(() => {}); return result;
  }
  async changes(uid, cursor, limit) {
    const all = this.user(uid).changes.filter(c => c.version > cursor);
    let changes = all.slice(0, limit);
    if (changes.length === limit && !changes.at(-1).groupEnd) { const end = changes.findLastIndex(c => c.groupEnd); if (end >= 0) changes = changes.slice(0,end+1); }
    return { changes: structuredClone(changes), cursor: changes.at(-1)?.version || cursor, hasMore: all.length > changes.length };
  }
  async conflicts(uid) { const u = this.user(uid); return structuredClone([...u.conflicts.values()].filter(c => c.status === 'open').map(c => { const e = u.entities.get(`${c.table}:${c.entityId}`); return { ...c, version: e.version, remote: { data: e.data, deleted: e.deleted, deviceId: e.deviceId } }; })); }
  async file(uid, hash) { return this.user(uid).files.get(hash); }
  async saveFile(uid, hash, data) { this.user(uid).files.set(hash, data); }
}
module.exports = { MemorySyncStore };
