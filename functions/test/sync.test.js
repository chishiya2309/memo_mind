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
