const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { FirestoreSyncStore } = require('../src/sync/adapters');

test('Firestore sync transactions, receipts, staged groups, conflicts and isolation', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  const app = initializeApp({ projectId: 'demo-memomind' }, `sync-${randomUUID()}`);
  const db = getFirestore(app), store = new FirestoreSyncStore(db), uid = `sync-${randomUUID()}`;
  const deck = { deck_id: 'd', title: 'Deck', description: null, tone: 'indigo', card_count: 0, tags: '[]', status: 'active', created_at: 1, updated_at: 1 };
  const op = (data, baseVersion = 0, fields = Object.keys(data)) => ({ operationId: randomUUID(), table: 'decks', entityId: data.deck_id, data, baseVersion, fields, deleted: false });
  try {
    await store.initialize(uid, 'explicit-source');
    const original = op(deck);
    const receipt = await store.push(uid, 'seed', 'phone', [original]);
    assert.deepEqual(await store.push(uid, 'seed', 'phone', [original]), receipt);
    assert.deepEqual((await store.push(uid, 'same-operation-new-group', 'phone', [original])).receipts, receipt.receipts);
    assert.equal((await store.status(uid)).revision, 1);
    await assert.rejects(store.push(uid, 'reused-operation', 'phone', [{ ...original, data: { ...deck, title: 'Changed' } }]), /Mã thay đổi/);
    const edits = [op({ ...deck, title: 'Phone' }, 1, ['title']), op({ ...deck, description: 'Tablet description' }, 1, ['description'])];
    await Promise.all(edits.map((edit, i) => store.push(uid, `edit-${i}`, i ? 'tablet' : 'phone', [edit])));
    const current = (await store.root(uid).collection('entities').doc('decks:d').get()).data();
    assert.equal(current.data.title, 'Phone');
    assert.equal(current.data.description, 'Tablet description');
    await store.push(uid, 'conflicting', 'tablet', [op({ ...deck, title: 'Tablet' }, 1, ['title'])]);
    const [conflict] = await store.conflicts(uid);
    assert.equal(conflict.local.data.title, 'Tablet');
    const resolve = [op({ ...current.data, title: 'Combined' }, conflict.version)];
    await store.push(uid, 'resolution', 'tablet', resolve, conflict.conflictId);
    await store.push(uid, 'resolution', 'tablet', resolve, conflict.conflictId);
    assert.equal((await store.conflicts(uid)).length, 0);
    const staged = Array.from({ length: 121 }, (_, i) => op({ ...deck, deck_id: `bulk-${i}` }));
    const before = (await store.status(uid)).revision;
    for (let i = 0; i < 3; i++) await store.stage(uid, { groupId: 'bulk', deviceId: 'phone', partIndex: i, partsCount: 3, restore: false, operations: staged.slice(i * 50, (i + 1) * 50) });
    assert.equal((await store.status(uid)).revision, before);
    await store.commit(uid, 'bulk');
    assert.equal((await store.status(uid)).revision, before + 121);
    const first = await store.changes(uid, before, 100), second = await store.changes(uid, first.cursor, 100);
    assert.equal(first.changes.length, 100);
    assert.equal(first.changes.at(-1).groupEnd, false);
    assert.equal(second.changes.length, 21);
    assert.equal(second.changes.at(-1).groupEnd, true);
    assert.equal((await store.changes(`${uid}-other`, 0, 100)).changes.length, 0);
    const invalid = { ...op({ ...deck, deck_id: 'bad' }), table: 'cards', entityId: 'missing', data: { card_id: 'missing', deck_id: 'absent' }, fields: [] };
    const revision = (await store.status(uid)).revision;
    await assert.rejects(store.push(uid, 'rollback', 'phone', [op({ ...deck, deck_id: 'rolled-back' }), invalid]), /nguồn/);
    assert.equal((await store.status(uid)).revision, revision);
    assert.equal((await store.root(uid).collection('entities').doc('decks:rolled-back').get()).exists, false);
  } finally {
    await db.recursiveDelete(store.root(uid));
    await deleteApp(app);
  }
});
