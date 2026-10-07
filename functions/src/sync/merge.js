const { canonical, fail } = require('../backup/validation');
const { ApiError } = require('../validation');
const { contentFields, ignoredFields, primaryKeys, key, validateOperation, validateRow, parents } = require('./schema');
const equal = (a, b) => canonical(a ?? null) === canonical(b ?? null);
const atomicGroups = {
  cards: [contentFields, ['source_document_id','source_page_id','source_page_number','source_block_id','source_quote']],
  documents: [['original_file_name','original_file_relative_path','original_file_mime_type','original_file_size_bytes','original_file_sha256']],
  source_pages: [['data_relative_path','mime_type','file_size_bytes','width','height','sha256']],
  page_normalizations: [['revision','normalized_relative_path','mime_type','file_size_bytes','width','height','sha256','top_left_x','top_left_y','top_right_x','top_right_y','bottom_right_x','bottom_right_y','bottom_left_x','bottom_left_y','rotation_degrees','contrast']],
  source_blocks: [['document_id','page_id','page_number','raw_text','normalized_text','status','box_left','box_top','box_width','box_height','box_image_sha256','has_valid_box']],
};
const scheduleKey = row => [row.reviewed_at || 0, row.device_id || '', row.event_id || ''];
function newerSchedule(a, b) {
  const ak = scheduleKey(a), bk = scheduleKey(b);
  for (let i = 0; i < ak.length; i++) if (ak[i] !== bk[i]) return ak[i] > bk[i];
  return false;
}
function mergeOperations(existing, operations, { revision = 0, deviceId, resolveConflictId, restore = false } = {}) {
  const entities = new Map(existing), changes = [], conflicts = [], receipts = [];
  for (const raw of operations) {
    const op = validateOperation(raw), entityKey = key(op.table, op.entityId), old = entities.get(entityKey);
    if (!op.deleted) {
      const parentKeys = parents(op.table, op.data);
      const dependencies = parentKeys.map(k => entities.get(k));
      if (dependencies.some(e => !e)) {
        const error = new ApiError(409, 'missing_parent', 'Dữ liệu nguồn chưa được đồng bộ.');
        error.missingParents = parentKeys.filter(k => !entities.has(k)).map(k => {
            const separator = k.indexOf(':');
            return { table: k.slice(0, separator), entityId: k.slice(separator + 1) };
        });
        throw error;
      }
      if (op.table !== 'review_events' && dependencies.some(e => e.deleted)) {
        if (op.table === 'card_schedules') { receipts.push({ operationId: op.operationId, version: old?.version || 0 }); continue; }
        const conflictId = op.operationId;
        const tombstone = { table: op.table, entityId: op.entityId, data: old?.data || op.data, deleted: true, version: ++revision, fieldVersions: old?.fieldVersions || {}, deviceId };
        entities.set(entityKey, tombstone); changes.push(tombstone);
        conflicts.push({ conflictId, table: op.table, entityId: op.entityId, local: { data: op.data, deleted: false, deviceId }, remote: { data: tombstone.data, deleted: true, deviceId: old?.deviceId || deviceId }, version: tombstone.version, status: 'open' });
        receipts.push({ operationId: op.operationId, version: tombstone.version, conflictId }); continue;
      }
    }
    if (op.baseVersion > (old?.version || 0)) fail('invalid_version', 'Phiên bản gốc chưa tồn tại.', 409);
    if (op.table === 'review_events' && old) {
      if (!equal(old.data, op.data) || op.deleted) fail('event_conflict', 'Mã lần ôn đã được sử dụng.', 409);
      receipts.push({ operationId: op.operationId, version: old.version }); continue;
    }
    if (op.table === 'card_schedules' && old && !restore && !newerSchedule(op.data, old.data)) { receipts.push({ operationId: op.operationId, version: old.version }); continue; }
    let data = old ? { ...old.data } : { ...op.data }, deleted = old?.deleted || false;
    const fields = [...new Set(op.fields)].filter(f => f !== primaryKeys[op.table] && !ignoredFields.has(f));
    const checkFields = new Set(fields);
    for (const atomic of atomicGroups[op.table] || []) {
      if (fields.some(f => atomic.includes(f))) atomic.forEach(f => checkFields.add(f));
    }
    const conflicting = old && [...checkFields].some(f => (old.fieldVersions?.[f] || 0) > op.baseVersion && !equal(old.data[f], op.data[f]));
    const deleteConflict = old && (op.deleted !== old.deleted) && op.baseVersion < old.version;
    if ((conflicting || deleteConflict || (old?.deleted && !op.deleted && !restore)) && !resolveConflictId && op.table !== 'card_schedules') {
      const conflictId = op.operationId;
      conflicts.push({ conflictId, table: op.table, entityId: op.entityId, local: { data: op.data, deleted: op.deleted, deviceId }, remote: { data: old.data, deleted: old.deleted, deviceId: old.deviceId }, version: old.version, status: 'open' });
      if (op.deleted && !deleted) deleted = true;
      else { receipts.push({ operationId: op.operationId, version: old.version, conflictId }); continue; }
    } else {
      for (const f of checkFields) data[f] = op.data[f] ?? null;
      if ('updated_at' in op.data) data.updated_at = op.data.updated_at;
      deleted = op.deleted;
    }
    if (op.table === 'card_schedules') { data = { ...op.data }; deleted = op.deleted; }
    if (!deleted) validateRow(op.table, data);
    const version = ++revision, fieldVersions = { ...(old?.fieldVersions || {}) };
    for (const f of checkFields) fieldVersions[f] = version;
    const entity = { table: op.table, entityId: op.entityId, data, deleted, version, fieldVersions, deviceId };
    entities.set(entityKey, entity); changes.push(entity);
    receipts.push({ operationId: op.operationId, version, ...(conflicts.some(c => c.conflictId === op.operationId) ? { conflictId: op.operationId } : {}) });
  }
  return { entities, changes, conflicts, receipts, revision };
}
module.exports = { mergeOperations, newerSchedule };
