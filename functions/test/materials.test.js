const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../src/app');
const { createProviders } = require('../src/providers');
const { validateRequest, filterCards } = require('../src/validation');

const block = { blockId: 'b', documentId: 'd', pageNumber: 1, normalizedText: 'Hà Nội là thủ đô. x-y khác x+y.' };
const request = { documentId: 'd', types: ['BASIC', 'CLOZE', 'MCQ'], quantityMode: 'auto', sourceBlocks: [block] };
const basic = { type: 'BASIC', front: 'Thủ đô?', back: 'Hà Nội', sourceBlockId: 'b',
  sourcePage: 1, sourceQuote: 'Hà Nội là thủ đô.', confidence: null,
  options: null, correctOptionId: null, explanation: null };
const cloze = { ...basic, type: 'CLOZE', front: '[...] là thủ đô.' };
const mcq = { ...basic, type: 'MCQ', front: 'Chọn thủ đô?', back: 'ignored',
  options: ['Hà Nội','Huế','Đà Nẵng','Cần Thơ'].map((text,i) => ({ optionId: 'ABCD'[i], text })),
  correctOptionId: 'A', explanation: 'Nguồn nêu Hà Nội là thủ đô.' };

async function withServer(options, run) {
  const server = createApp(options).listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  const post = async (body = request, path = '/api/v1/materials/generate') => {
    const response = await fetch(base + path, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  try { await run(post); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}

test('all types preserve sources; MCQ back derived from correct option', () => {
  const r = filterCards([basic, cloze, mcq], validateRequest(request));
  assert.equal(r.validCount, 3);
  assert.deepEqual(r.countsByType, { BASIC: 1, CLOZE: 1, MCQ: 1 });
  assert.equal(r.cards[2].back, 'Hà Nội');
});
test('each type can be generated separately', () => {
  for(const card of [basic, cloze, mcq]) {
    const r = filterCards([card], validateRequest({ ...request, types: [card.type] }));
    assert.equal(r.validCount, 1);
  }
});
test('request validates types/count/source ownership before calling provider', () => {
  for (const patch of [
    { types: [] }, { types: ['BAD'] }, { types: ['BASIC','BASIC'] },
    { quantityMode: 'manual', desiredCount: 2 }, { quantityMode: 'manual', desiredCount: 31 },
    { quantityMode: 'manual', desiredCount: 3.5 },
    { sourceBlocks: [{ ...block, documentId: 'other' }] },
    { sourceBlocks: [block, block] }, { sourceBlocks: [{ ...block, normalizedText: ' ' }] },
    { sourceBlocks: [{ ...block, pageNumber: 1.5 }] },
  ]) assert.throws(() => validateRequest({ ...request, ...patch }));
  assert.throws(() => validateRequest({ ...request, sourceBlocks: [{ ...block, normalizedText: 'x'.repeat(100001) }] }),
    error => error.status === 413);
});
test('schema, fields, source page and source quote are rejected, never repaired', () => {
  const invalid = [
    null, { ...basic, front: 2 }, { ...basic, extra: 'bad' }, { ...basic, back: ' ' },
    { ...basic, sourceBlockId: 'other' }, { ...basic, sourcePage: 2 },
    { ...basic, sourceQuote: 'x y' }, { ...basic, confidence: 2 },
    { ...basic, front: 'a'.repeat(2001) }, { ...cloze, front: 'No blank' },
    { ...basic, type: 'UNKNOWN' }, { ...basic, options: [] },
    { ...mcq, options: mcq.options.slice(0,3) },
    { ...mcq, options: mcq.options.map(o => ({ ...o, text: 'Hà Nội' })) },
    { ...mcq, options: mcq.options.map(o => ({ ...o, optionId: 'A' })) },
    { ...mcq, correctOptionId: 'E' }, { ...mcq, explanation: '' },
  ];
  const r = filterCards([...invalid, basic], validateRequest(request));
  assert.equal(r.validCount, 1); assert.equal(r.discardedCount, invalid.length);
  assert.equal(invalid[5].sourcePage, 2);
});
test('Unicode normalization accepts equivalent accents, preserves punctuation and case', () => {
  const r = filterCards([{ ...basic, sourceQuote: basic.sourceQuote.normalize('NFD') }], validateRequest(request));
  assert.equal(r.validCount, 1);
  assert.equal(filterCards([{ ...basic, sourceQuote: 'hà nội' }], validateRequest(request)).validCount, 0);
});
test('auto capped at 20, manual capped at desiredCount, dedup counted', () => {
  const cards = Array.from({length: 35}, (_,i) => ({ ...basic, front: 'Q' + i }));
  assert.equal(filterCards(cards, validateRequest(request)).validCount, 20);
  const r = filterCards([basic, basic, ...cards], validateRequest({ ...request, quantityMode: 'manual', desiredCount: 3 }));
  assert.equal(r.validCount, 3);
  assert.equal(r.discardedCount, 34);
});
test('repair malformed envelope exactly once and retain partial valid result', async () => {
  let calls = 0;
  await withServer({ providers: { generate: async (req, signal, previous) => {
    calls++; assert.equal(previous !== undefined, calls === 2);
    return calls === 1 ? 'not json' : JSON.stringify({ cards: [basic, { ...cloze, sourcePage: 9 }] });
  } } }, async post => {
    const r = await post();
    assert.equal(r.status, 200); assert.equal(r.body.validCount, 1); assert.equal(r.body.discardedCount, 1);
  });
  assert.equal(calls, 2);
});
test('second malformed envelope is an explicit error', async () => {
  let calls = 0;
  await withServer({ providers: { generate: async () => { calls++; return '{}'; } } }, async post => {
    const r = await post(); assert.equal(r.status, 502); assert.equal(r.body.error, 'invalid_llm_output');
  });
  assert.equal(calls, 2);
});
test('invalid items are dropped without repair; zero valid -> 422', async () => {
  let calls = 0;
  await withServer({ providers: { generate: async () => { calls++; return '{"cards":[null]}'; } } }, async post => {
    const r = await post(); assert.equal(r.status, 422); assert.equal(r.body.discardedCount, 1);
  });
  assert.equal(calls, 1);
});
test('deadline aborts provider; does not retry timeout', async () => {
  let calls = 0, signal;
  await withServer({ deadlineMs: 10, providers: { generate: async (_, s) => {
    calls++; signal = s; return new Promise(() => {});
  } } }, async post => {
    assert.equal((await post()).status, 504);
    assert.equal(signal.aborted, true);
  });
  assert.equal(calls, 1);
});
test('legacy route preserves old wire shape', async () => {
  await withServer({ providers: { generate: async req => {
    assert.deepEqual(req.types, ['BASIC']);
    return JSON.stringify({ cards: [basic] });
  } } }, async post => {
    const r = await post({ documentId:'d', format:'qa', desiredCount:1,
      sourceBlocks:[{ blockId:'b', pageNumber:1, normalizedText:block.normalizedText }] },
      '/api/v1/materials/flashcards/generate');
    assert.equal(r.status,200); assert.equal(r.body.cards[0].question,basic.front);
    assert.equal(r.body.cards[0].format,'qa');
  });
});
test('rate limit returns Retry-After', async () => {
  await withServer({ rateLimit: 1, providers: { generate: async () => JSON.stringify({cards:[basic]}) } }, async post => {
    assert.equal((await post()).status,200);
    const r=await post(); assert.equal(r.status,429); assert.ok(Number(r.headers.get('retry-after'))>0);
  });
});
test('OCR validates bytes, limit, and returns text through provider', async () => {
  let calls=0;
  await withServer({ providers: { enhance: async body => { calls++; assert.equal(body.currentText,'old');return {text:'new'}; } } }, async post => {
    const path='/api/v1/ocr/enhance';
    assert.equal((await post({imageBase64:'garbage'},path)).status,400);
    assert.equal((await post({imageBase64:Buffer.alloc(5*1024*1024+1).toString('base64')},path)).status,413);
    const r=await post({imageBase64:Buffer.from([255,216,255,217]).toString('base64'),currentText:'old'},path);
    assert.equal(r.status,200);assert.equal(r.body.text,'new'); assert.equal(calls,1);
  });
});
test('missing provider keys/model and HTTP quota/auth errors mapped safely', async () => {
  const empty=createProviders({},async()=>{throw Error('must not call');});
  await assert.rejects(empty.generate(validateRequest(request)), e=>e.status===503);
  await assert.rejects(empty.enhance({}),e=>e.status===503);
  for(const [status,expected] of [[429,429],[401,503],[403,503],[500,502]]) {
    const p=createProviders({GROQ_API_KEY:'test-key'},async()=>({status,ok:false}));
    await assert.rejects(p.generate(validateRequest(request)),e=>e.status===expected);
  }
});
test('Groq/Gemini use separate server keys and configurable model', async () => {
  const seen=[];
  const p=createProviders({GROQ_API_KEY:'groq-secret',GROQ_MODEL:'groq-model',
    GEMINI_API_KEY:'gemini-secret',GEMINI_MODEL:'gemini-model'},async(url,options)=>{
      seen.push({url,options,body:JSON.parse(options.body)});
      return {ok:true,status:200,json:async()=>url.includes('groq.com')
        ?{choices:[{message:{content:'{"cards":[]}'}}]}:{candidates:[{content:{parts:[{text:'OCR'}]}}]}};
    });
  await p.generate(validateRequest(request));
  await p.enhance({imageBase64:'abcd'});
  assert.equal(seen[0].options.headers.Authorization,'Bearer groq-secret');
  assert.equal(seen[0].body.model,'groq-model');
  assert.equal(seen[0].body.response_format.type,'json_schema');
  assert.ok(seen[1].url.includes('/gemini-model:generateContent'));
  assert.equal(seen[1].options.headers['x-goog-api-key'],'gemini-secret');
});
