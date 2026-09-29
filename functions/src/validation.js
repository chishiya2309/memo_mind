const { validateCardSchema } = require('./schema');
const TYPES = ['BASIC', 'CLOZE', 'MCQ'];
const normalize = value => value.normalize('NFC').replace(/\s+/gu, ' ').trim();
const boundedText = (value, max) => typeof value === 'string' && value.trim().length > 0 && value.length <= max;
class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
function validateRequest(body) {
  const bad = () => { throw new ApiError(400, 'invalid_request', 'Cấu hình hoặc nguồn học liệu không hợp lệ.'); };
  if (!body || !boundedText(body.documentId, 200) || !Array.isArray(body.types) ||
      !body.types.length || new Set(body.types).size !== body.types.length ||
      body.types.some(t => !TYPES.includes(t))) bad();
  const quantityMode = body.quantityMode ?? 'auto';
  if (!['auto', 'manual'].includes(quantityMode)) bad();
  if (quantityMode === 'manual' && (!Number.isInteger(body.desiredCount) ||
      body.desiredCount < body.types.length || body.desiredCount > 30)) bad();
  if (!Array.isArray(body.sourceBlocks) || !body.sourceBlocks.length || body.sourceBlocks.length > 10000) bad();
  const ids = new Set(); let chars = 0;
  for (const b of body.sourceBlocks) {
    if (!b || !boundedText(b.blockId, 200) || ids.has(b.blockId) ||
        b.documentId !== body.documentId || !Number.isInteger(b.pageNumber) || b.pageNumber < 1 ||
        typeof b.normalizedText !== 'string' || !b.normalizedText.trim()) bad();
    ids.add(b.blockId); chars += b.normalizedText.length;
  }
  if (chars > 100000) throw new ApiError(413, 'payload_too_large', 'Vui lòng chọn ít đoạn nguồn hơn (tối đa 100.000 ký tự).');
  return { ...body, quantityMode, limit: quantityMode === 'auto' ? 20 : body.desiredCount };
}
function rejectionReason(card, request, blocks) {
  if (!validateCardSchema(card)) return 'invalid_schema';
  if (!request.types.includes(card.type)) return 'unrequested_type';
  if (!boundedText(card.front, 2000) || !boundedText(card.back, 2000) ||
      !boundedText(card.sourceQuote, 2000) ||
      (card.confidence !== null && (!Number.isFinite(card.confidence) || card.confidence < 0 || card.confidence > 1))) return 'invalid_fields';
  if (card.type === 'CLOZE' && !card.front.includes('[...]')) return 'invalid_cloze';
  if (card.type === 'MCQ') {
    if (!Array.isArray(card.options) || card.options.length !== 4 ||
        new Set(card.options.map(o => o.optionId)).size !== 4 ||
        card.options.some(o => !boundedText(o.text, 500)) ||
        new Set(card.options.map(o => normalize(o.text).toLowerCase())).size !== 4 ||
        !card.options.some(o => o.optionId === card.correctOptionId) ||
        !boundedText(card.explanation, 2000)) return 'invalid_mcq';
  } else if (card.options !== null || card.correctOptionId !== null || card.explanation !== null) return 'invalid_fields';
  const block = blocks.get(card.sourceBlockId);
  if (!block || block.documentId !== request.documentId) return 'source_block_mismatch';
  if (card.sourcePage !== block.pageNumber) return 'source_page_mismatch';
  if (!normalize(block.normalizedText).includes(normalize(card.sourceQuote))) return 'unsupported_quote';
  return null;
}
function filterCards(rawCards, request) {
  const blocks = new Map(request.sourceBlocks.map(b => [b.blockId, b]));
  const seen = new Set(); const cards = []; const counts = new Map();
  const reject = code => counts.set(code, (counts.get(code) || 0) + 1);
  for (const raw of rawCards) {
    const reason = rejectionReason(raw, request, blocks);
    if (reason) { reject(reason); continue; }
    const key = normalize(raw.front).toLowerCase();
    if (seen.has(key)) { reject('duplicate'); continue; }
    if (cards.length >= request.limit) { reject('count_limit'); continue; }
    seen.add(key);
    const card = { ...raw, front: raw.front.trim(), back: raw.back.trim() };
    if (card.type === 'MCQ') {
      card.options = card.options.map(o => ({ ...o, text: o.text.trim() })).sort((a, b) => a.optionId.localeCompare(b.optionId));
      card.back = card.options.find(o => o.optionId === card.correctOptionId).text;
    }
    cards.push(card);
  }
  const countsByType = Object.fromEntries(TYPES.map(t => [t, cards.filter(c => c.type === t).length]));
  const warnings = [...counts].map(([code, count]) => ({ code, count }));
  for (const type of request.types) if (!countsByType[type]) warnings.push({ code: 'missing_type', type, count: 0 });
  if (request.quantityMode === 'manual' && cards.length < request.limit) warnings.push({ code: 'fewer_than_requested', count: request.limit - cards.length });
  return { cards, totalGenerated: rawCards.length, validCount: cards.length,
    discardedCount: rawCards.length - cards.length, countsByType, warnings };
}
function parseEnvelope(text) {
  try {
    const body = JSON.parse(text);
    return body && !Array.isArray(body) && Object.keys(body).length === 1 && Array.isArray(body.cards) ? body.cards : null;
  } catch { return null; }
}
module.exports = { ApiError, validateRequest, filterCards, parseEnvelope, normalize };
