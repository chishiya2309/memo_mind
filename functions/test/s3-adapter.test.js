const test = require('node:test');
const assert = require('node:assert/strict');
const { S3Client } = require('@aws-sdk/client-s3');
const { S3Objects } = require('../src/backup/adapters');

test('presigned upload binds checksum, content length and create-only condition for ten minutes', async () => {
  const client = new S3Client({ region: 'ap-southeast-1', credentials: { accessKeyId: 'TESTONLY', secretAccessKey: 'fake-credential-for-offline-test' } });
  const objects = new S3Objects({ bucket: 'test-memomind', client });
  try {
    const result = await objects.uploadUrl('staging/A/w/b.zip', { bundleHash: 'a'.repeat(64), sizeBytes: 123 });
    const url = new URL(result.url);
    assert.equal(url.searchParams.get('X-Amz-Expires'), '600');
    for (const header of ['if-none-match', 'x-amz-checksum-sha256', 'content-length', 'content-type']) assert.ok(url.searchParams.get('X-Amz-SignedHeaders').split(';').includes(header));
    assert.equal(result.headers['If-None-Match'], '*');
    assert.equal(result.headers['Content-Length'], '123');
    assert.equal(result.headers['x-amz-checksum-sha256'], Buffer.from('a'.repeat(64), 'hex').toString('base64'));
    assert.equal(url.pathname, '/staging/A/w/b.zip');
  } finally { client.destroy(); }
});
