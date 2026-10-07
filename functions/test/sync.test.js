const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../src/app');
const { MemorySyncStore } = require('./sync-support.cjs');
const { newerSchedule } = require('../src/sync/merge');
const deck = { deck_id: 'd', title: 'Deck', description: null, tone: 'indigo', card_count: 0, tags: '[]', status: 'active', created_at: 1, updated_at: 1 };
const card = { card_id: 'c', deck_id: 'd', type: 'BASIC', front: 'Q', back: 'A', mcq_payload: null, tags: '[]', source_document_id: null, source_page_id: null, source_page_number: null, source_block_id: null, source_quote: '', confidence: null, status: 'active', created_at: 1, updated_at: 1 };
let id = 0;
const op = (table, data, baseVersion = 0, fields = Object.keys(data), deleted = false) => ({ operationId: `op-${++id}`, table, entityId: data[({ decks:'deck_id',cards:'card_id',card_schedules:'card_id',review_sessions:'session_id',review_events:'event_id' })[table]], data, baseVersion, fields, deleted });
async function seeded() { const store = new MemorySyncStore(); await store.initialize('A','source'); await store.push('A','seed','phone',[op('decks',deck),op('cards',card)]); return store; }
test('two devices merge independent card fields, and duplicate requests are identical', async () => {
  const store = await seeded(), base = store.user('A').entities.get('cards:c').version;
  const ops = [op('cards',{...card, front:'New Q'},base,['front'])];
  const first = await store.push('A','edit-A','phone',ops);
  assert.deepEqual(await store.push('A','edit-A','phone',ops), first);
  await store.push('A','edit-B','tablet',[op('cards',{...card,tags:'["word"]'},base,['tags'])]);
  const row = store.user('A').entities.get('cards:c');
  assert.equal(row.data.front, 'New Q'); assert.equal(row.data.tags, '["word"]');
  assert.equal((await store.conflicts('A')).length, 0);
  await assert.rejects(store.push('A','edit-A','phone',[op('cards',card)]), /Mã thao tác/);
});
test('question and answer are one atomic content group; both conflicting versions are retained', async () => {
  const store = await seeded(), base = store.user('A').entities.get('cards:c').version;
  await store.push('A','a','phone',[op('cards',{...card, front:'Q2'},base,['front'])]);
  await store.push('A','b','tablet',[op('cards',{...card, back:'A2'},base,['back'])]);
  const [conflict] = await store.conflicts('A');
  assert.equal(conflict.local.data.back,'A2'); assert.equal(conflict.remote.data.front,'Q2');
  await store.push('A','resolve','tablet',[op('cards',{...card,front:'Q2',back:'A2'},conflict.version)],conflict.conflictId);
  assert.equal((await store.conflicts('A')).length,0);
  assert.equal(store.user('A').entities.get('cards:c').data.back,'A2');
});
test('delete wins against concurrent edits; stale devices cannot resurrect a deleted deck child', async () => {
  const store = await seeded(), base = store.user('A').entities.get('cards:c').version;
  await store.push('A','delete','phone',[op('cards',{...card,status:'deleted'},base,['status'],true)]);
  await store.push('A','offline-edit','tablet',[op('cards',{...card,front:'Offline'},base,['front'])]);
  assert.equal(store.user('A').entities.get('cards:c').deleted,true);
  await store.push('A','delete-deck','phone',[op('decks',{...deck,status:'deleted'},1,['status'],true)]);
  await store.push('A','late-card','tablet',[op('cards',{...card,card_id:'late'})]);
  assert.equal(store.user('A').entities.get('cards:late').deleted,true);
  assert.equal((await store.conflicts('A')).length,2);
});
test('latest review selects schedule without summing branch schedules; ties are deterministic', async () => {
  const store = await seeded();
  const schedule = {card_id:'c',repetitions:1,interval_days:1,ease_factor:2.5,due_date:86400001,reviewed_at:10,device_id:'A',event_id:'eA',scheduler_version:'sm2-v1'};
  await store.push('A','review-a','A',[op('card_schedules',schedule)]);
  await store.push('A','review-b','B',[op('card_schedules',{...schedule,reviewed_at:20,repetitions:2,interval_days:6,event_id:'eB',device_id:'B'})]);
  await store.push('A','old-offline','A',[op('card_schedules',{...schedule,reviewed_at:15,repetitions:3})]);
  assert.equal(store.user('A').entities.get('card_schedules:c').data.repetitions,2);
  assert.equal(newerSchedule({...schedule,device_id:'B'},schedule),true);
});
test('failed atomic group rolls back entirely and pagination ends on a group boundary', async () => {
  const store = await seeded(); const revision = store.user('A').revision;
  await assert.rejects(store.push('A','invalid','phone',[op('decks',{...deck,deck_id:'new'}),op('cards',{...card,card_id:'bad',deck_id:'missing'})]),/nguồn/);
  assert.equal(store.user('A').revision,revision); assert.equal(store.user('A').entities.has('decks:new'),false);
  for (let n=0;n<4;n++) await store.push('A',`batch-${n}`,'phone',[op('decks',{...deck,deck_id:`d${n}`}),op('cards',{...card,card_id:`c${n}`,deck_id:`d${n}`})]);
  const page = await store.changes('A',0,5);
  assert.equal(page.changes.length,4); assert.equal(page.changes.at(-1).groupEnd,true);
});
test('API isolates accounts, requires verification, and validates operation limits and paths', async () => {
  const store = await seeded();
  const app = createApp({sync:{store,verifyToken:async token => { if(token==='bad') throw Object.assign(Error(), {code:'auth/invalid-id-token'}); return {uid:token,email_verified:token!=='unverified'}; }}});
  const server = app.listen(0,'127.0.0.1'); await new Promise(r=>server.once('listening',r));
  async function request(path,token='A',body) { const r=await fetch(`http://127.0.0.1:${server.address().port}/api/v1/sync${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:r.status,body:await r.json()}; }
  try {
    assert.equal((await request('/status','bad')).status,401);
    assert.equal((await request('/status','unverified')).status,403);
    assert.equal((await request('/changes','B')).body.changes.length,0);
    assert.equal((await request('/push','A',{groupId:'g',deviceId:'d',operations:Array.from({length:51},()=>op('decks',deck))})).status,400);
    assert.equal((await request('/push','A',{groupId:'g',deviceId:'d',operations:[op('cards',{...card,source_page_id:'p',malicious:'x'})]})).status,400);
  } finally { server.closeAllConnections(); await new Promise(r=>server.close(r)); }
});

test('missing_parent identifies the prerequisite and rejects the whole transaction', async () => {
  const store = await seeded();
  const app = createApp({ sync: { store, verifyToken: async () => ({ uid: 'A', email_verified: true }) } });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const revision = store.user('A').revision;
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/v1/sync/push`, {
      method: 'POST', headers: { Authorization: 'Bearer A', 'Content-Type': 'application/json' },
      body: JSON.stringify({ groupId: 'missing-parent', deviceId: 'phone', operations: [
        op('decks', { ...deck, deck_id: 'must-rollback' }),
        op('cards', { ...card, card_id: 'orphan', deck_id: 'missing-deck' }),
      ] }),
    });
    assert.equal(response.status, 409);
    const body = await response.json();
    assert.equal(body.error, 'missing_parent');
    assert.deepEqual(body.missingParents, [{ table: 'decks', entityId: 'missing-deck' }]);
    assert.equal(store.user('A').revision, revision);
    assert.equal(store.user('A').entities.has('decks:must-rollback'), false);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('source text and its geometry are atomic, including v10 packets without image binding', async () => {
  const store = new MemorySyncStore();
  await store.initialize('A', 'source');
  const doc = { document_id: 'doc', title: 'PDF', status: 'ready_for_generation', privacy: 'private',
    page_count: 1, original_file_name: null, original_file_relative_path: null,
    original_file_mime_type: null, original_file_size_bytes: null, original_file_sha256: null,
    created_at: 1, updated_at: 1 };
  const page = { page_id: 'page', document_id: 'doc', page_number: 1, original_page_number: 7,
    source: 'pdf', data_relative_path: 'documents/doc/page.png', mime_type: 'image/png',
    file_size_bytes: 1, width: 800, height: 1000, sha256: 'a'.repeat(64), quality_code: 'good',
    quality_warning_accepted: 0, created_at: 1, normalization_status: 'source_ready' };
  const block = { block_id: 'block', document_id: 'doc', page_id: 'page', page_number: 1,
    order_index: 0, raw_text: 'Evidence', normalized_text: 'Evidence', box_left: .1,
    box_top: .2, box_width: .5, box_height: .3, has_valid_box: 1, confidence: null,
    confidence_source: 'unavailable', status: 'verified', created_at: 1, updated_at: 1 };
  const sourceOp = (table, entityId, data, baseVersion = 0, fields = Object.keys(data)) => ({
    operationId: `source-${++id}`, table, entityId, data, baseVersion, fields, deleted: false,
  });
  await store.push('A', 'source-seed', 'phone', [sourceOp('documents', 'doc', doc),
    sourceOp('source_pages', 'page', page), sourceOp('source_blocks', 'block', block)]);
  const base = store.user('A').entities.get('source_blocks:block').version;
  await store.push('A', 'correct-text', 'phone', [sourceOp('source_blocks', 'block', {
    ...block, normalized_text: 'Corrected evidence', box_image_sha256: page.sha256,
  }, base, ['normalized_text', 'box_image_sha256'])]);
  await store.push('A', 'other-geometry', 'tablet', [sourceOp('source_blocks', 'block', {
    ...block, box_top: .8, box_image_sha256: 'b'.repeat(64),
  }, base, ['box_top', 'box_image_sha256'])]);
  const current = store.user('A').entities.get('source_blocks:block').data;
  assert.equal(current.normalized_text, 'Corrected evidence');
  assert.equal(current.box_top, .2);
  assert.equal(current.box_image_sha256, page.sha256);
  assert.equal((await store.conflicts('A')).length, 1);
  // A later v10 client has no image binding. Its complete source group must
  // clear the v11 fingerprint instead of trusting old geometry on a new row.
  const currentVersion = store.user('A').entities.get('source_blocks:block').version;
  await store.push('A', 'legacy-source-edit', 'old-phone', [sourceOp('source_blocks', 'block', {
    ...block, normalized_text: 'Legacy correction', box_top: .4,
  }, currentVersion, ['normalized_text', 'box_top'])]);
  const legacy = store.user('A').entities.get('source_blocks:block').data;
  assert.equal(legacy.box_image_sha256, null);
  assert.equal(legacy.normalized_text, 'Legacy correction');
  assert.equal(legacy.box_top, .4);
});

test('card source IDs and evidence cannot be merged from different devices', async () => {
  const store = await seeded();
  const base = store.user('A').entities.get('cards:c').version;
  await store.push('A', 'source-link', 'phone', [op('cards', {
    ...card, source_document_id: 'doc', source_page_id: 'page', source_page_number: 1,
    source_block_id: 'block', source_quote: 'Evidence',
  }, base, ['source_document_id', 'source_page_id', 'source_page_number', 'source_block_id', 'source_quote'])]);
  await store.push('A', 'source-quote', 'tablet', [op('cards', {
    ...card, source_quote: 'Different evidence',
  }, base, ['source_quote'])]);
  assert.equal(store.user('A').entities.get('cards:c').data.source_quote, 'Evidence');
  assert.equal((await store.conflicts('A')).length, 1);
});
