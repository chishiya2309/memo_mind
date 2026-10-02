const express = require('express');
const { ApiError } = require('../validation');
const { limits, validateRequest, inspectArchive, fail } = require('./validation');
const { configuredAdapters } = require('./adapters');

const immutableFields = ['backupId', 'workspaceId', 'bundleHash', 'manifestHash', 'fingerprint', 'sizeBytes', 'fileCount', 'schemaVersion', 'schedulerVersion', 'snapshotRevision', 'snapshotAt'];
const keys = job => ({ staging: `staging/${job.ownerUid}/${job.workspaceId}/${job.backupId}.zip`, ready: `ready/${job.ownerUid}/${job.workspaceId}/${job.backupId}.zip` });
function backupRouter(injected) {
  const router = express.Router(); let dependencies = injected;
  const asyncRoute = action => (req, res, next) => Promise.resolve(action(req, res, next)).catch(next);
  router.use(asyncRoute(async (req, _, next) => {
    dependencies ||= configuredAdapters();
    if (!dependencies) fail('backup_not_configured', 'Dịch vụ sao lưu chưa được cấu hình.', 503);
    const token = /^Bearer (\S+)$/.exec(req.headers.authorization || '')?.[1];
    if (!token) fail('reauth_required', 'Cần đăng nhập lại.', 401);
    let identity;
    try { identity = await dependencies.verifyToken(token); } catch { fail('reauth_required', 'Cần đăng nhập lại.', 401); }
    if (!identity?.uid || identity.email_verified !== true) fail('email_unverified', 'Xác minh email để dùng sao lưu.', 403);
    req.uid = identity.uid; next();
  }));
  router.use(express.json({ limit: '32kb' }));
  async function owned(req) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(req.params.backupId)) fail('invalid_backup', 'ID không hợp lệ.');
    const job = await dependencies.metadata.get(req.uid, req.params.backupId);
    if (!job || job.ownerUid !== req.uid) fail('backup_not_found', 'Không tìm thấy bản sao.', 404);
    return job;
  }
  router.get('/', asyncRoute(async (req, res) => res.json({ backups: (await dependencies.metadata.list(req.uid)).filter(j => j.status !== 'deleted').sort((a, b) => b.snapshotAt - a.snapshotAt), limits })));
  router.get('/:backupId', asyncRoute(async (req, res) => res.json({ backup: await owned(req), limits })));
  router.post('/', asyncRoute(async (req, res) => {
    const requested = validateRequest(req.body, req.uid);
    const job = await dependencies.metadata.change(req.uid, requested.backupId, requested.workspaceId, (existing, workspace) => {
      if (existing) {
        if (existing.status === 'deleted' || existing.status === 'deleting' || immutableFields.some(k => existing[k] !== requested[k])) fail('backup_conflict', 'Không thể dùng lại ID cho dữ liệu khác.', 409);
        return { value: existing };
      }
      if (workspace.lastFingerprint === requested.fingerprint && workspace.lastReadyId) return { value: { duplicateId: workspace.lastReadyId } };
      if (workspace.readyCount >= limits.maxReady) fail('backup_quota', 'Đã có 5 bản sao. Hãy chọn bản cần xóa.', 409);
      if (workspace.pendingId) fail('backup_busy', 'Kho đang có một tác vụ chưa hoàn tất.', 409);
      const created = { ...requested, ownerUid: req.uid, status: 'uploading', createdAt: Date.now(), completedAt: null };
      return { job: created, workspace: { ...workspace, pendingId: created.backupId }, value: created };
    });
    if (job.duplicateId) return res.json({ backup: await dependencies.metadata.get(req.uid, job.duplicateId), duplicate: true, limits });
    if (job.status === 'ready') return res.json({ backup: job, limits });
    res.json({ backup: job, upload: await dependencies.objects.uploadUrl(keys(job).staging, job), limits });
  }));
  router.post('/:backupId/finalize', asyncRoute(async (req, res) => {
    let job = await owned(req);
    if (job.status === 'ready') return res.json({ backup: job });
    const lease = require('node:crypto').randomUUID();
    job = await dependencies.metadata.change(req.uid, job.backupId, job.workspaceId, (j, w) => {
      if (!j || ['deleted', 'deleting'].includes(j.status)) fail('backup_conflict', 'Bản sao đã bị hủy.', 409);
      if (j.status === 'ready') return { value: j };
      if (j.leaseUntil > Date.now()) fail('backup_busy', 'Bản sao đang được kiểm tra.', 409);
      const next = { ...j, status: 'verifying', lease, leaseUntil: Date.now() + limits.timeoutMs };
      return { job: next, value: next };
    });
    if (job.status === 'ready') return res.json({ backup: job });
    const objectKeys = keys(job);
    try {
      const ready = await dependencies.objects.head(objectKeys.ready);
      const source = ready ? objectKeys.ready : objectKeys.staging;
      const head = ready || await dependencies.objects.head(source);
      if (!head || head.ContentLength !== job.sizeBytes) fail('incomplete_backup', 'Chưa tải đủ gói dữ liệu.', 409);
      const counts = await inspectArchive(await dependencies.objects.read(source), job);
      if (!ready) await dependencies.objects.promote(source, objectKeys.ready);
      const acknowledged = await dependencies.objects.head(objectKeys.ready);
      if (!acknowledged || acknowledged.ContentLength !== job.sizeBytes) fail('incomplete_backup', 'Chưa xác nhận được tệp hoàn tất.', 409);
      const completed = await dependencies.metadata.change(req.uid, job.backupId, job.workspaceId, (j, w) => {
        if (j.status === 'ready') return { value: j };
        if (j.lease !== lease || w.pendingId !== j.backupId) fail('backup_conflict', 'Tác vụ đã thay đổi.', 409);
        const next = { ...j, ...counts, status: 'ready', objectKey: objectKeys.ready, completedAt: Date.now(), leaseUntil: 0, lastError: null };
        return { job: next, workspace: { ...w, pendingId: null, readyCount: w.readyCount + 1, lastFingerprint: j.fingerprint, lastReadyId: j.backupId }, value: next };
      });
      res.json({ backup: completed });
    } catch (e) {
      await dependencies.metadata.change(req.uid, job.backupId, job.workspaceId, j => j?.lease === lease && j.status !== 'ready' ? { job: { ...j, leaseUntil: 0, status: 'uploading', lastError: e.code || 'backup_failed' } } : {});
      throw e instanceof ApiError ? e : new ApiError(503, 'backup_unavailable', 'Dịch vụ sao lưu chưa xác nhận kết quả. Hãy đối chiếu và thử lại.');
    }
  }));
  router.post('/:backupId/download-url', asyncRoute(async (req, res) => {
    const job = await owned(req);
    if (job.status !== 'ready') fail('incomplete_backup', 'Bản sao chưa hoàn tất.', 409);
    res.json({ backup: job, url: await dependencies.objects.downloadUrl(keys(job).ready), expiresAt: Date.now() + limits.urlSeconds * 1000 });
  }));
  router.delete('/:backupId', asyncRoute(async (req, res) => {
    const job = await owned(req);
    const deleting = await dependencies.metadata.change(req.uid, job.backupId, job.workspaceId, j => {
      if (j.status === 'deleted') return { value: j };
      if (j.leaseUntil > Date.now()) fail('backup_busy', 'Đợi bước kiểm tra hoàn tất rồi thử lại.', 409);
      const next = { ...j, status: 'deleting', wasReady: j.wasReady || j.status === 'ready' };
      return { job: next, value: next };
    });
    if (deleting.status !== 'deleted') {
      const objectKeys = keys(job);
      await dependencies.objects.delete(objectKeys.ready); await dependencies.objects.delete(objectKeys.staging);
      await dependencies.metadata.change(req.uid, job.backupId, job.workspaceId, (j, w) => {
        if (j.status === 'deleted') return {};
        return { job: { ...j, status: 'deleted' }, workspace: { ...w, readyCount: Math.max(0, w.readyCount - (j.wasReady ? 1 : 0)), pendingId: w.pendingId === j.backupId ? null : w.pendingId, lastReadyId: w.lastReadyId === j.backupId ? null : w.lastReadyId, lastFingerprint: w.lastReadyId === j.backupId ? null : w.lastFingerprint } };
      });
    }
    res.json({ deleted: true });
  }));
  return router;
}
module.exports = { backupRouter, keys };
