const { fail, safeKey } = require('../backup/validation');
const columns = {
  documents: 'document_id title status privacy page_count original_file_name original_file_relative_path original_file_mime_type original_file_size_bytes original_file_sha256 created_at updated_at',
  source_pages: 'page_id document_id page_number original_page_number source data_relative_path mime_type file_size_bytes width height sha256 quality_code quality_warning_accepted created_at normalization_status',
  page_normalizations: 'page_id revision normalized_relative_path mime_type file_size_bytes width height sha256 top_left_x top_left_y top_right_x top_right_y bottom_right_x bottom_right_y bottom_left_x bottom_left_y rotation_degrees contrast updated_at',
  ocr_page_results: 'page_id document_id status recognized_language raw_full_text error_message updated_at',
  source_blocks: 'block_id page_id document_id page_number order_index raw_text normalized_text box_left box_top box_width box_height box_image_sha256 has_valid_box confidence confidence_source status created_at updated_at',
  decks: 'deck_id title description tone card_count tags status created_at updated_at',
  cards: 'card_id deck_id type front back mcq_payload tags source_document_id source_page_id source_page_number source_block_id source_quote confidence status created_at updated_at',
  review_sessions: 'session_id deck_id due_only initial_count status created_at updated_at device_id',
  review_events: 'event_id session_id card_id device_id reviewed_at rating schedule_after scheduler_version',
  card_schedules: 'card_id repetitions interval_days ease_factor due_date reviewed_at device_id event_id scheduler_version',
};
const primaryKeys = { documents: 'document_id', source_pages: 'page_id', page_normalizations: 'page_id', ocr_page_results: 'page_id', source_blocks: 'block_id', decks: 'deck_id', cards: 'card_id', review_sessions: 'session_id', review_events: 'event_id', card_schedules: 'card_id' };
const contentFields = ['type', 'front', 'back', 'mcq_payload'];
const ignoredFields = new Set(['updated_at', 'card_count', 'page_count']);
const key = (table, id) => `${table}:${id}`;
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
function parents(table, data) {
  const fields = { source_pages: [['documents','document_id']], page_normalizations: [['source_pages','page_id']], ocr_page_results: [['documents','document_id'],['source_pages','page_id']], source_blocks: [['documents','document_id'],['source_pages','page_id']], cards: [['decks','deck_id']], card_schedules: [['cards','card_id']], review_events: [['review_sessions','session_id']] };
  return (fields[table] || []).map(([t, f]) => key(t, data[f]));
}
function validateOperation(op) {
  if (!op || !validId(op.operationId) || !primaryKeys[op.table] || !validId(op.entityId) || !Number.isSafeInteger(op.baseVersion) || op.baseVersion < 0 || typeof op.deleted !== 'boolean') fail('invalid_sync', 'Thao tác đồng bộ không hợp lệ.');
  if (!op.data || typeof op.data !== 'object' || Array.isArray(op.data) || op.data[primaryKeys[op.table]] !== op.entityId) fail('invalid_sync', 'ID dữ liệu không khớp.');
  const allowed = new Set(columns[op.table].split(' '));
  if (Object.keys(op.data).some(f => !allowed.has(f)) || !Array.isArray(op.fields) || op.fields.some(f => !allowed.has(f))) fail('invalid_sync', 'Trường đồng bộ không được hỗ trợ.');
  if (Buffer.byteLength(JSON.stringify(op)) > 128 * 1024) fail('sync_limit', 'Một đối tượng đồng bộ quá lớn.', 413);
  for (const [f, v] of Object.entries(op.data)) {
    if (v !== null && !['string', 'number'].includes(typeof v)) fail('invalid_sync', 'Giá trị đồng bộ không hợp lệ.');
    if (typeof v === 'number' && !Number.isFinite(v)) fail('invalid_sync', 'Giá trị số không hợp lệ.');
    if (f.endsWith('relative_path') && v !== null && (!safeKey(v) || !v.startsWith('documents/'))) fail('invalid_sync', 'Đường dẫn tệp không hợp lệ.');
  }
  return op;
}
function validateRow(table, row) {
  const reject = () => fail('invalid_sync', 'Dữ liệu học không hợp lệ.');
  const integer = (f, min = 0) => Number.isSafeInteger(row[f]) && row[f] >= min;
  const choice = (f, values) => values.includes(row[f]);
  const text = f => typeof row[f] === 'string';
  const unit = f => row[f] === null || (typeof row[f] === 'number' && row[f] >= 0 && row[f] <= 1);
  // v10 clients and frozen packets do not contain the nullable geometry binding.
  if (columns[table].split(' ').some(f => f !== 'box_image_sha256' && !Object.hasOwn(row, f))) reject();
  for (const f of ['created_at', 'updated_at']) if (columns[table].split(' ').includes(f) && !integer(f)) reject();
  if ('tags' in row) {
    let tags; try { tags = JSON.parse(row.tags); } catch { reject(); }
    if (!Array.isArray(tags) || tags.some(t => typeof t !== 'string')) reject();
  }
  if (table === 'documents') {
    if (!text('title') || row.privacy !== 'private' || !integer('page_count') || !choice('status', ['pending_processing','pending_ocr','pending_ocr_review','ready_for_generation'])) reject();
    const fileFields = ['original_file_name','original_file_relative_path','original_file_mime_type','original_file_size_bytes','original_file_sha256'];
    if (row.original_file_relative_path === null) { if (fileFields.some(f => row[f] !== null)) reject(); }
    else if (!text('original_file_name') || row.original_file_mime_type !== 'application/pdf' || !integer('original_file_size_bytes',1) || !/^[a-f0-9]{64}$/.test(row.original_file_sha256)) reject();
  }
  if (table === 'source_pages' || table === 'page_normalizations') {
    if (!integer('file_size_bytes',1) || !integer('width',1) || !integer('height',1) || !/^[a-f0-9]{64}$/.test(row.sha256)) reject();
    if (table === 'source_pages') {
      if (!validId(row.document_id) || !integer('page_number',1) || !integer('original_page_number',1) || !choice('source',['camera','gallery','pdf']) || !choice('mime_type',['image/jpeg','image/png']) || !choice('normalization_status',['pending','ready','source_ready']) || !text('quality_code') || !choice('quality_warning_accepted',[0,1])) reject();
    } else if (!integer('revision',1) || row.mime_type !== 'image/png' || !choice('rotation_degrees',[0,90,180,270]) || typeof row.contrast !== 'number' || Math.abs(row.contrast)>0.5 || ['top_left_x','top_left_y','top_right_x','top_right_y','bottom_right_x','bottom_right_y','bottom_left_x','bottom_left_y'].some(f => row[f] === null || !unit(f))) reject();
  }
  if (table === 'ocr_page_results' && (!validId(row.document_id) || (row.raw_full_text !== null && !text('raw_full_text')) || !choice('status',['not_started','processing','completed','failed']))) reject();
  if (table === 'source_blocks' && (!validId(row.page_id) || !validId(row.document_id) || !integer('page_number',1) || !integer('order_index') || !text('raw_text') || !text('normalized_text') || !choice('has_valid_box',[0,1]) || !choice('confidence_source',['mlkit','gemini','user','unavailable']) || !choice('status',['draft','needs_review','verified','user_added','deleted']) || ['box_left','box_top','box_width','box_height','confidence'].some(f => !unit(f)))) reject();
  if (table === 'source_blocks' && row.box_image_sha256 != null && !/^[a-f0-9]{64}$/.test(row.box_image_sha256)) reject();
  if (table === 'cards') {
    if (!['BASIC', 'CLOZE', 'MCQ'].includes(row.type) || !['active', 'suspended', 'deleted'].includes(row.status) || typeof row.front !== 'string' || typeof row.back !== 'string' || !validId(row.deck_id)) fail('invalid_sync', 'Nội dung thẻ không hợp lệ.');
    if (row.type === 'MCQ' && row.status === 'active') {
      let mcq; try { mcq = JSON.parse(row.mcq_payload); } catch { fail('invalid_sync', 'Câu hỏi trắc nghiệm không hợp lệ.'); }
      if (!mcq || !Array.isArray(mcq.options) || mcq.options.length !== 4 || new Set(mcq.options.map(o => o?.optionId)).size !== 4 || mcq.options.some(o => !validId(o?.optionId) || typeof o.text !== 'string' || !o.text.trim()) || !mcq.options.some(o => o.optionId === mcq.correctOptionId && o.text === row.back) || typeof mcq.explanation !== 'string') fail('invalid_sync', 'Câu hỏi trắc nghiệm không hợp lệ.');
    }
    if (row.type !== 'MCQ' && row.mcq_payload !== null) fail('invalid_sync', 'Cấu trúc thẻ không hợp lệ.');
    if (!unit('confidence') || (row.source_page_number !== null && !integer('source_page_number',1))) reject();
  }
  if (table === 'review_events' && (!['again', 'hard', 'good', 'easy'].includes(row.rating) || !Number.isSafeInteger(row.reviewed_at) || !validId(row.session_id) || !validId(row.card_id) || !validId(row.device_id))) fail('invalid_sync', 'Lần ôn không hợp lệ.');
  if (table === 'card_schedules' && (![row.repetitions, row.interval_days, row.due_date, row.reviewed_at].every(Number.isSafeInteger) || row.repetitions < 0 || row.interval_days < 0 || row.ease_factor < 1.3 || row.scheduler_version !== 'sm2-v1')) fail('invalid_sync', 'Lịch ôn không hợp lệ.');
  if (table === 'decks' && (typeof row.title !== 'string' || !['active', 'deleted'].includes(row.status) || !choice('tone',['indigo','teal','blue','amber','rose','violet']) || !integer('card_count'))) fail('invalid_sync', 'Bộ thẻ không hợp lệ.');
  if (table === 'review_sessions' && (!['active','ended','completed'].includes(row.status) || ![0,1].includes(row.due_only) || !Number.isInteger(row.initial_count) || row.initial_count < 0)) fail('invalid_sync', 'Phiên ôn không hợp lệ.');
}
module.exports = { columns, primaryKeys, contentFields, ignoredFields, key, validId, validateOperation, validateRow, parents };
