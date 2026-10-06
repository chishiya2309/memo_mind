const express = require('express');
const { fail } = require('../backup/validation');
const { validId, validateOperation } = require('./schema');
const { configuredSyncAdapters } = require('./adapters');
const { authenticate } = require('../authentication');
function syncRouter(injected) {
  const router = express.Router(); let dependencies = injected;
  const route = action => (req, res, next) => Promise.resolve(action(req, res)).catch(next);
  router.use((req, res, next) => {
    const started = Date.now();
    res.once('finish', () => {
      if (process.env.SYNC_METRICS === 'true') console.info(JSON.stringify({ event: 'sync_request', method: req.method, route: req.route?.path || 'authentication', status: res.statusCode, durationMs: Date.now() - started, operationCount: Array.isArray(req.body?.operations) ? req.body.operations.length : 0 }));
    });
    next();
  });
  router.use((req, res, next) => Promise.resolve().then(async () => {
    dependencies ||= configuredSyncAdapters();
    if (!dependencies) fail('sync_not_configured', 'Dịch vụ đồng bộ chưa được cấu hình.', 503);
    await authenticate(req, res, token => dependencies.verifyToken(token)); next();
  }).catch(next));
  router.use(express.json({ limit: '1mb' }));
  router.get('/status', route(async (req, res) => res.json(await dependencies.store.status(req.uid))));
  router.post('/initialize', route(async (req, res) => {
    if (!validId(req.body.sourceId)) fail('invalid_sync', 'Nguồn chuyển đổi không hợp lệ.');
    res.json(await dependencies.store.initialize(req.uid, req.body.sourceId));
  }));
  const push = (resolve, restore = false) => route(async (req, res) => {
    const { groupId, deviceId, operations } = req.body;
    if (!validId(groupId) || !validId(deviceId) || !Array.isArray(operations) || !operations.length || operations.length > 50) fail('sync_limit', 'Mỗi yêu cầu cần từ 1 đến 50 thao tác.');
    operations.forEach(validateOperation);
    if (new Set(operations.map(op => op.operationId)).size !== operations.length) fail('invalid_sync', 'Mã thao tác bị trùng.');
    if (resolve && !validId(req.params.conflictId)) fail('invalid_sync', 'Xung đột không hợp lệ.');
    res.json(await dependencies.store.push(req.uid, groupId, deviceId, operations, resolve ? req.params.conflictId : undefined, restore));
  });
  router.post('/push', push(false));
  router.post('/restore', push(false, true));
  router.post('/stage', route(async (req,res) => {
    const b = req.body;
    if (!validId(b.groupId) || !validId(b.deviceId) || !Number.isInteger(b.partIndex) || !Number.isInteger(b.partsCount) || b.partsCount<1 || b.partsCount>100 || b.partIndex<0 || b.partIndex>=b.partsCount || typeof b.restore!=='boolean' || !Array.isArray(b.operations) || !b.operations.length || b.operations.length>50) fail('invalid_sync', 'Nhóm đồng bộ không hợp lệ.');
    b.operations.forEach(validateOperation);
    if (Buffer.byteLength(JSON.stringify(b)) > 900 * 1024) fail('sync_limit', 'Phần dữ liệu quá lớn.', 413);
    res.json(await dependencies.store.stage(req.uid, {groupId:b.groupId,deviceId:b.deviceId,partIndex:b.partIndex,partsCount:b.partsCount,restore:b.restore,operations:b.operations}));
  }));
  router.post('/commit', route(async (req,res) => {
    if (!validId(req.body.groupId)) fail('invalid_sync', 'Mã nhóm không hợp lệ.');
    res.json(await dependencies.store.commit(req.uid,req.body.groupId));
  }));
  router.post('/conflicts/:conflictId/resolve', push(true));
  router.get('/changes', route(async (req, res) => {
    const cursor = Number(req.query.cursor || 0), limit = Number(req.query.limit || 100);
    if (!Number.isSafeInteger(cursor) || cursor < 0 || !Number.isInteger(limit) || limit < 1 || limit > 100) fail('invalid_sync', 'Vị trí đồng bộ không hợp lệ.');
    res.json(await dependencies.store.changes(req.uid, cursor, limit));
  }));
  router.get('/conflicts', route(async (req, res) => res.json({ conflicts: await dependencies.store.conflicts(req.uid) })));
  router.post('/files/:hash', route(async (req, res) => {
    const hash = req.params.hash, { sizeBytes, mimeType } = req.body;
    if (!/^[a-f0-9]{64}$/.test(hash) || !Number.isSafeInteger(sizeBytes) || sizeBytes <= 0 || sizeBytes > 100 * 1024 * 1024 || !['image/png', 'image/jpeg', 'application/pdf'].includes(mimeType)) fail('invalid_file', 'Tệp nguồn không hợp lệ.');
    const key = `sync/${req.uid}/files/${hash}`, head = await dependencies.objects.head(key);
    if (head) {
      if (head.ContentLength !== sizeBytes || head.ChecksumSHA256 !== Buffer.from(hash, 'hex').toString('base64')) fail('checksum_mismatch', 'Tệp nguồn hỏng.');
      await dependencies.store.saveFile(req.uid, hash, { key, sizeBytes, mimeType }); return res.json({ ready: true });
    }
    res.json({ ready: false, upload: await dependencies.objects.uploadUrl(key, { bundleHash: hash, sizeBytes, mimeType }) });
  }));
  router.get('/files/:hash', route(async (req, res) => {
    if (!/^[a-f0-9]{64}$/.test(req.params.hash)) fail('invalid_file', 'Checksum không hợp lệ.');
    const file = await dependencies.store.file(req.uid, req.params.hash);
    if (!file) fail('file_pending', 'Tệp nguồn chưa đồng bộ.', 404);
    res.json({ ...file, url: await dependencies.objects.downloadUrl(file.key) });
  }));
  return router;
}
module.exports = { syncRouter };
