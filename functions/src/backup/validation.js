const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');
const yauzl = require('yauzl');
const { ApiError } = require('../validation');

const limits = Object.freeze({ maxBytes: 100 * 1024 * 1024, maxFiles: 1000, maxReady: 5, urlSeconds: 600, timeoutMs: 600000 });
const tables = ['documents', 'source_pages', 'page_normalizations', 'ocr_page_results', 'source_blocks', 'decks', 'cards', 'review_sessions', 'review_events'];
const canonical = value => JSON.stringify(sort(value));
function sort(value) {
  if (Array.isArray(value)) return value.map(sort);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, sort(value[k])]));
  return value;
}
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const fail = (code, message, status = 400) => { throw new ApiError(status, code, message); };
const safeKey = key => typeof key === 'string' && key.length <= 500 && !key.includes('\\') && !key.startsWith('/') && key.split('/').every(s => s && s !== '.' && s !== '..' && !s.includes(':'));
const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
function validateRequest(body, uid) {
  if (!body || !id(body.backupId) || !id(body.workspaceId) || (body.ownerUid !== undefined && body.ownerUid !== uid)) fail('invalid_backup', 'Thông tin bản sao không hợp lệ.');
  for (const field of ['bundleHash', 'manifestHash', 'fingerprint']) if (!/^[a-f0-9]{64}$/.test(body[field] ?? '')) fail('invalid_backup', 'Checksum không hợp lệ.');
  if (!Number.isSafeInteger(body.sizeBytes) || body.sizeBytes <= 0 || body.sizeBytes > limits.maxBytes || !Number.isSafeInteger(body.fileCount) || body.fileCount < 0 || body.fileCount > limits.maxFiles) fail('backup_limit', 'Bản sao vượt giới hạn.', 413);
  if (body.schemaVersion !== 9 || body.schedulerVersion !== 'sm2-v1' || !Number.isSafeInteger(body.snapshotRevision) || body.snapshotRevision < 0 || !Number.isSafeInteger(body.snapshotAt)) fail('incompatible_backup', 'Phiên bản bản sao không được hỗ trợ.');
  const fields = ['backupId', 'workspaceId', 'bundleHash', 'manifestHash', 'fingerprint', 'sizeBytes', 'fileCount', 'schemaVersion', 'schedulerVersion', 'snapshotRevision', 'snapshotAt'];
  return Object.fromEntries(fields.map(k => [k, body[k]]));
}

async function inspectArchive(stream, expected, { signal } = {}) {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'memomind-backup-'));
  const filename = path.join(directory, 'snapshot.zip');
  let actualBytes = 0;
  const digest = crypto.createHash('sha256');
  const { Transform } = require('node:stream');
  try {
    await pipeline(stream, new Transform({ transform(chunk, _, cb) {
      actualBytes += chunk.length;
      if (actualBytes > limits.maxBytes) return cb(new ApiError(413, 'backup_limit', 'Gói quá lớn.'));
      digest.update(chunk); cb(null, chunk);
    }}), fs.createWriteStream(filename), { signal });
    if (actualBytes !== expected.sizeBytes || digest.digest('hex') !== expected.bundleHash) fail('checksum_mismatch', 'Checksum gói không khớp.');
    const zip = await new Promise((resolve, reject) => yauzl.open(filename, { lazyEntries: true, validateEntrySizes: true }, (e, z) => e ? reject(new ApiError(400, 'invalid_archive', 'Gói ZIP không hợp lệ.')) : resolve(z)));
    const entries = new Map();
    let expanded = 0;
    await new Promise((resolve, reject) => {
      const rejectAndClose = e => { zip.close(); reject(e instanceof ApiError ? e : new ApiError(400, 'invalid_archive', 'Gói ZIP không hợp lệ.')); };
      const abort = () => rejectAndClose(new ApiError(504, 'backup_timeout', 'Kiểm tra ZIP quá thời gian chờ.'));
      if (signal) {
        signal.addEventListener('abort', abort, { once: true });
        zip.once('close', () => signal.removeEventListener('abort', abort));
        if (signal.aborted) return abort();
      }
      zip.on('error', rejectAndClose);
      zip.on('end', resolve);
      zip.on('entry', entry => {
        const name = entry.fileName;
        if (!safeKey(name) || entries.has(name) || name.endsWith('/') || entries.size >= limits.maxFiles + 2 || (entry.generalPurposeBitFlag & 1) || ((entry.externalFileAttributes >>> 16) & 0xf000) === 0xa000) return rejectAndClose(new ApiError(400, 'invalid_archive', 'Đường dẫn hoặc mục ZIP không hợp lệ.'));
        zip.openReadStream(entry, async (error, input) => {
          if (error) return rejectAndClose(error);
          try {
            const h = crypto.createHash('sha256'); let bytes = 0; const chunks = [];
            for await (const chunk of input) {
              bytes += chunk.length; expanded += chunk.length;
              if (expanded > limits.maxBytes) throw new ApiError(413, 'backup_limit', 'Dữ liệu giải nén quá lớn.');
              h.update(chunk);
              if (name === 'data.json' || name === 'manifest.json') chunks.push(chunk);
            }
            entries.set(name, { sizeBytes: bytes, sha256: h.digest('hex'), bytes: chunks.length ? Buffer.concat(chunks) : null });
            zip.readEntry();
          } catch (e) { rejectAndClose(e); }
        });
      });
      zip.readEntry();
    });
    const manifestEntry = entries.get('manifest.json'); const dataEntry = entries.get('data.json');
    if (!manifestEntry || !dataEntry || manifestEntry.sha256 !== expected.manifestHash) fail('invalid_manifest', 'Thiếu manifest hoặc checksum không khớp.');
    let manifest, data;
    try { manifest = JSON.parse(manifestEntry.bytes); data = JSON.parse(dataEntry.bytes); } catch { fail('invalid_archive', 'JSON không hợp lệ.'); }
    if (!manifest || typeof manifest !== 'object' || !data || typeof data !== 'object') fail('invalid_archive', 'JSON không hợp lệ.');
    for (const key of ['ownerUid', 'backupId', 'workspaceId', 'schemaVersion', 'schedulerVersion', 'snapshotRevision', 'snapshotAt', 'fingerprint']) if (manifest[key] !== expected[key]) fail('invalid_manifest', 'Manifest không thuộc bản sao đã đăng ký.');
    if (manifest.dataHash !== dataEntry.sha256 || !Array.isArray(manifest.files) || manifest.files.length !== expected.fileCount || entries.size !== manifest.files.length + 2) fail('invalid_manifest', 'Phạm vi tệp không khớp.');
    const keys = new Set();
    for (const file of manifest.files) {
      const actual = entries.get(`files/${file.fileKey}`);
      if (!safeKey(file.fileKey) || !file.fileKey.startsWith('documents/') || keys.has(file.fileKey) || !actual || actual.sizeBytes !== file.sizeBytes || actual.sha256 !== file.sha256) fail('checksum_mismatch', 'Tệp nguồn thiếu hoặc hỏng.');
      keys.add(file.fileKey);
    }
    if (!data.tables || Object.keys(data.tables).sort().join() !== [...tables].sort().join() || tables.some(t => !Array.isArray(data.tables[t]) || data.tables[t].some(row => !row || typeof row !== 'object' || Array.isArray(row)))) fail('invalid_data', 'Bảng dữ liệu không hợp lệ.');
    const fingerprint = hash(canonical({ schemaVersion: 9, schedulerVersion: 'sm2-v1', dataHash: dataEntry.sha256, files: manifest.files }));
    if (fingerprint !== expected.fingerprint) fail('checksum_mismatch', 'Dấu vân tay nội dung không khớp.');
    const fileMap = new Map(manifest.files.map(f => [f.fileKey, f]));
    const references = [ ...data.tables.documents.filter(r => r.original_file_relative_path).map(r => [r.original_file_relative_path, r.original_file_size_bytes, r.original_file_sha256]), ...data.tables.source_pages.map(r => [r.data_relative_path, r.file_size_bytes, r.sha256]), ...data.tables.page_normalizations.map(r => [r.normalized_relative_path, r.file_size_bytes, r.sha256]) ];
    if (references.some(([key, size, checksum]) => !fileMap.has(key) || fileMap.get(key).sizeBytes !== size || fileMap.get(key).sha256 !== checksum)) fail('missing_source', 'Tệp nguồn tham chiếu không khớp metadata.');
    const primaryKeys = { documents: 'document_id', source_pages: 'page_id', page_normalizations: 'page_id', ocr_page_results: 'page_id', source_blocks: 'block_id', decks: 'deck_id', cards: 'card_id', review_sessions: 'session_id', review_events: 'event_id' };
    const ids = {};
    for (const table of tables) {
      ids[table] = new Set();
      for (const row of data.tables[table]) {
        const key = row?.[primaryKeys[table]];
        if (typeof key !== 'string' || !key || ids[table].has(key)) fail('invalid_data', 'ID thực thể không hợp lệ hoặc trùng.');
        ids[table].add(key);
      }
    }
    for (const row of data.tables.source_pages) if (!ids.documents.has(row.document_id)) fail('invalid_data', 'Trang nguồn không có tài liệu.');
    for (const table of ['page_normalizations', 'ocr_page_results', 'source_blocks']) for (const row of data.tables[table]) if (!ids.source_pages.has(row.page_id)) fail('invalid_data', 'Thành phần nguồn không có trang.');
    for (const row of data.tables.cards) if (!ids.decks.has(row.deck_id)) fail('invalid_data', 'Thẻ không có deck.');
    for (const row of data.tables.review_events) if (!ids.review_sessions.has(row.session_id)) fail('invalid_data', 'Sự kiện không có phiên ôn.');
    return { deckCount: data.tables.decks.filter(r => r.status === 'active').length, cardCount: data.tables.cards.filter(r => r.status === 'active').length };
  } finally { await fs.promises.rm(directory, { recursive: true, force: true }); }
}
module.exports = { limits, tables, canonical, hash, safeKey, validateRequest, inspectArchive, fail };
