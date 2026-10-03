const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { inspectArchive } = require('../src/backup/validation');

test('Node validates the ZIP/fingerprint produced by Flutter with MCQ and review history', { skip: !process.env.FR18_FLUTTER_FIXTURE }, async () => {
  const root = process.env.FR18_FLUTTER_FIXTURE;
  const expected = JSON.parse(fs.readFileSync(path.join(root, 'snapshot.json'), 'utf8'));
  const result = await inspectArchive(fs.createReadStream(path.join(root, 'snapshot.zip')), expected);
  assert.equal(result.deckCount, 1);
  assert.equal(result.cardCount, 1);
});
