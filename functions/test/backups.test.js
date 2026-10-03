const test = require('node:test');
const assert = require('node:assert/strict');
const { Readable } = require('node:stream');
const { createApp } = require('../src/app');
const { canonical, hash, tables, inspectArchive } = require('../src/backup/validation');
const { keys } = require('../src/backup/router');

function zip(entries) {
  const local = [], central = []; let offset = 0;
  function crc(bytes) { let n = -1; for (const byte of bytes) { n ^= byte; for (let i = 0; i < 8; i++) n = (n >>> 1) ^ (0xedb88320 & -(n & 1)); } return (n ^ -1) >>> 0; }
  for (const [name, value] of entries) {
    const bytes = Buffer.from(value), filename = Buffer.from(name), header = Buffer.alloc(30), directory = Buffer.alloc(46);
    header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4); header.writeUInt32LE(crc(bytes), 14); header.writeUInt32LE(bytes.length, 18); header.writeUInt32LE(bytes.length, 22); header.writeUInt16LE(filename.length, 26);
    directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(20, 4); directory.writeUInt16LE(20, 6); directory.writeUInt32LE(crc(bytes), 16); directory.writeUInt32LE(bytes.length, 20); directory.writeUInt32LE(bytes.length, 24); directory.writeUInt16LE(filename.length, 28); directory.writeUInt32LE(offset, 42);
    local.push(header, filename, bytes); central.push(directory, filename); offset += header.length + filename.length + bytes.length;
  }
  const dir = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(dir.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, dir, end]);
}
function fixture({ backupId = 'backup-1', ownerUid = 'A', extra = [], source = false } = {}) {
  const records = Object.fromEntries(tables.map(t => [t, []]));
  const bytes = Buffer.from('%PDF-reference');
  const files = source ? [{ fileKey: 'documents/d/original.pdf', sizeBytes: bytes.length, sha256: hash(bytes) }] : [];
  if (source) records.documents.push({ document_id: 'd', original_file_relative_path: files[0].fileKey, original_file_size_bytes: bytes.length, original_file_sha256: hash(bytes) });
  const data = canonical({ tables: records });
  const fingerprint = hash(canonical({ schemaVersion: 9, schedulerVersion: 'sm2-v1', dataHash: hash(data), files }));
  const manifest = { ownerUid, backupId, workspaceId: 'workspace-1', snapshotRevision: 0, snapshotAt: 100, schemaVersion: 9, schedulerVersion: 'sm2-v1', fingerprint, dataHash: hash(data), files };
  const archive = zip([['data.json', data], ['manifest.json', canonical(manifest)], ...files.map(f => [`files/${f.fileKey}`, bytes]), ...extra]);
  const request = { ...manifest, sizeBytes: archive.length, fileCount: files.length, bundleHash: hash(archive), manifestHash: hash(canonical(manifest)) };
  delete request.files; delete request.dataHash;
  return { request, archive };
}
class MemoryMetadata {
  jobs = new Map(); workspaces = new Map(); tail = Promise.resolve();
  async get(uid, id) { return structuredClone(this.jobs.get(`${uid}/${id}`) || null); }
  async list(uid) { return [...this.jobs.values()].filter(j => j.ownerUid === uid).map(j => structuredClone(j)); }
  async change(uid, id, workspaceId, action) {
    const result = this.tail.then(() => {
      const jk = `${uid}/${id}`, wk = `${uid}/${workspaceId}`;
      const next = action(structuredClone(this.jobs.get(jk) || null), structuredClone(this.workspaces.get(wk) || { readyCount: 0, pendingId: null }));
      if (next.job) this.jobs.set(jk, structuredClone(next.job));
      if (next.workspace) this.workspaces.set(wk, structuredClone(next.workspace));
      return structuredClone(next.value);
    });
    this.tail = result.catch(() => {}); return result;
  }
}
class MemoryObjects {
  values = new Map(); promoted = 0; failDelete = false;
  async uploadUrl(key) { return { url: `https://s3.example/${key}`, headers: {}, expiresAt: Date.now() + 600000 }; }
  async head(key) { return this.values.has(key) ? { ContentLength: this.values.get(key).length, ChecksumSHA256: Buffer.from(hash(this.values.get(key)), 'hex').toString('base64') } : null; }
  async read(key) { return Readable.from(this.values.get(key)); }
  async promote(source, destination) { this.promoted++; this.values.set(destination, this.values.get(source)); }
  async downloadUrl(key) { return `https://s3.example/${key}`; }
  async delete(key) { if (this.failDelete) throw Error('storage outage'); this.values.delete(key); }
}
async function server(run, { timeoutMs } = {}) {
  const metadata = new MemoryMetadata(), objects = new MemoryObjects();
  const app = createApp({ backup: { metadata, objects, timeoutMs, verifyToken: async token => {
    if (token === 'bad') throw Error('invalid');
    return { uid: token === 'B' ? 'B' : 'A', email_verified: token !== 'unverified' };
  } } });
  const s = app.listen(0, '127.0.0.1'); await new Promise(resolve => s.once('listening', resolve));
  async function request(method, suffix = '', body, token = 'A') {
    const response = await fetch(`http://127.0.0.1:${s.address().port}/api/v1/backups${suffix}`, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  }
  try { await run({ request, metadata, objects }); }
  finally { s.closeAllConnections(); await new Promise(resolve => s.close(resolve)); }
}

test('rejects invalid tokens, unverified email, client-supplied UID, cross-account reads', () => server(async ({ request }) => {
  const f = fixture();
  assert.equal((await request('POST', '', f.request, 'bad')).status, 401);
  assert.equal((await request('POST', '', f.request, 'unverified')).status, 403);
  assert.equal((await request('POST', '', { ...f.request, ownerUid: 'B' })).status, 400);
  await request('POST', '', f.request);
  assert.equal((await request('GET', '/backup-1', undefined, 'B')).status, 404);
  assert.equal((await request('POST', '/backup-1/download-url', undefined, 'B')).status, 404);
}));
test('double begin is idempotent; changed content cannot reuse backup ID', () => server(async ({ request, metadata }) => {
  const f = fixture(); const results = await Promise.all([request('POST', '', f.request), request('POST', '', f.request)]);
  assert.deepEqual(results.map(r => r.status), [200, 200]); assert.equal(metadata.jobs.size, 1);
  assert.equal((await request('POST', '', { ...f.request, snapshotRevision: 1 })).status, 409);
  assert.equal((await request('POST', '', fixture({ backupId: 'another' }).request)).status, 409);
}));
test('full source archive completes only after verification, finalize retry does not duplicate', () => server(async ({ request, metadata, objects }) => {
  const f = fixture({ source: true }); await request('POST', '', f.request);
  assert.equal((await request('POST', '/backup-1/finalize')).status, 409);
  assert.equal((await metadata.get('A', 'backup-1')).status, 'uploading');
  objects.values.set(keys(f.request).staging, f.archive);
  const result = await request('POST', '/backup-1/finalize'); assert.equal(result.status, 200); assert.equal(result.body.backup.status, 'ready');
  assert.equal((await request('POST', '/backup-1/finalize')).status, 200); assert.equal(objects.promoted, 1);
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 1);
  assert.equal((await request('POST', '/backup-1/download-url')).status, 200);
  const duplicate = await request('POST', '', fixture({ backupId: 'same-content', source: true }).request); assert.equal(duplicate.body.duplicate, true);
}));
test('checksum failure preserves previous ready backup and quota is enforced', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); metadata.workspaces.set('A/workspace-1', { readyCount: 4, pendingId: null });
  await request('POST', '', f.request); objects.values.set(keys(f.request).staging, Buffer.alloc(f.archive.length));
  assert.equal((await request('POST', '/backup-1/finalize')).body.error, 'checksum_mismatch');
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 4);
  metadata.workspaces.set('A/workspace-1', { readyCount: 5, pendingId: null });
  assert.equal((await request('POST', '', fixture({ backupId: 'over-quota' }).request)).body.error, 'backup_quota');
  assert.equal((await request('POST', '', { ...f.request, sizeBytes: 101 * 1024 * 1024 })).status, 413);
}));
test('ZIP extra entries, duplicate names and missing source are rejected', async () => {
  const extra = fixture({ extra: [['unexpected.txt', 'private-cache']] });
  await assert.rejects(inspectArchive(Readable.from(extra.archive), extra.request), e => e.code === 'invalid_manifest');
  const duplicate = fixture({ extra: [['data.json', '{}']] });
  await assert.rejects(inspectArchive(Readable.from(duplicate.archive), duplicate.request), e => e.code === 'invalid_archive');
});
test('delete failure retains intermediate state and a retry adjusts quota exactly once', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); await request('POST', '', f.request); objects.values.set(keys(f.request).staging, f.archive); await request('POST', '/backup-1/finalize');
  objects.failDelete = true; assert.equal((await request('DELETE', '/backup-1')).status, 500);
  assert.equal((await metadata.get('A', 'backup-1')).status, 'deleting'); assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 1);
  objects.failDelete = false; assert.equal((await request('DELETE', '/backup-1')).status, 200); assert.equal((await request('DELETE', '/backup-1')).status, 200);
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 0);
  assert.equal((await request('POST', '/backup-1/download-url')).status, 409);
  assert.equal((await request('POST', '', f.request)).status, 409);
}));
module.exports = { fixture, zip, MemoryMetadata, MemoryObjects };

test('finalize recovers a completed S3 copy when the metadata commit failed', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); await request('POST', '', f.request); objects.values.set(keys(f.request).staging, f.archive);
  const change = metadata.change.bind(metadata); let failReady = true;
  metadata.change = (uid, id, workspace, action) => change(uid, id, workspace, (j, w) => {
    const result = action(j, w);
    if (failReady && result.job?.status === 'ready') { failReady = false; throw Error('metadata outage'); }
    return result;
  });
  assert.equal((await request('POST', '/backup-1/finalize')).status, 503);
  assert.equal((await metadata.get('A', 'backup-1')).status, 'uploading');
  assert.ok(objects.values.has(keys(f.request).ready));
  assert.equal((await request('POST', '/backup-1/finalize')).status, 200);
  assert.equal(objects.promoted, 1); assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 1);
}));

test('lost metadata commit response preserves ready and retry does not increment quota twice', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); await request('POST', '', f.request); objects.values.set(keys(f.request).staging, f.archive);
  const change = metadata.change.bind(metadata); let loseReady = true;
  metadata.change = async (...args) => {
    const result = await change(...args);
    if (loseReady && result?.status === 'ready') { loseReady = false; throw Error('lost response'); }
    return result;
  };
  assert.equal((await request('POST', '/backup-1/finalize')).status, 503);
  assert.equal((await request('GET', '/backup-1')).body.backup.status, 'ready');
  assert.equal((await request('POST', '/backup-1/finalize')).status, 200);
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 1);
}));

test('finalize lease blocks concurrent finalization and deletion', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); await request('POST', '', f.request); objects.values.set(keys(f.request).staging, f.archive);
  const promote = objects.promote.bind(objects); let markCopying, release;
  const copying = new Promise(resolve => { markCopying = resolve; });
  const held = new Promise(resolve => { release = resolve; });
  objects.promote = async (...args) => { markCopying(); await held; return promote(...args); };
  const first = request('POST', '/backup-1/finalize'); await copying;
  assert.equal((await request('POST', '/backup-1/finalize')).body.error, 'backup_busy');
  assert.equal((await request('DELETE', '/backup-1')).body.error, 'backup_busy');
  release(); assert.equal((await first).status, 200);
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 1);
}));

test('malformed ZIP and unsafe paths return a backup-specific archive error', async () => {
  const f = fixture(); const bad = Buffer.from('not-a-zip');
  await assert.rejects(inspectArchive(Readable.from(bad), { ...f.request, sizeBytes: bad.length, bundleHash: hash(bad) }), e => e.code === 'invalid_archive');
  const unsafe = fixture({ extra: [['../secret', 'x']] });
  await assert.rejects(inspectArchive(Readable.from(unsafe.archive), unsafe.request), e => e.code === 'invalid_archive');
});
test('finalize timeout aborts a stalled S3 stream and releases its lease for retry', () => server(async ({ request, metadata, objects }) => {
  const f = fixture(); await request('POST', '', f.request); objects.values.set(keys(f.request).staging, f.archive);
  objects.read = async () => new Readable({ read() {} });
  const response = await request('POST', '/backup-1/finalize');
  assert.equal(response.status, 504); assert.equal(response.body.error, 'backup_timeout');
  assert.equal((await metadata.get('A', 'backup-1')).status, 'uploading');
  assert.equal(metadata.workspaces.get('A/workspace-1').readyCount, 0);
}, { timeoutMs: 30 }));