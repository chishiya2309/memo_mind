const express = require('express');
const cors = require('cors');
const { createProviders } = require('./providers');
const { ApiError, validateRequest, filterCards, parseEnvelope } = require('./validation');
async function withinDeadline(work, milliseconds) {
  const controller = new AbortController(); let timer;
  try {
    return await Promise.race([work(controller.signal), new Promise((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new ApiError(504, 'provider_timeout', 'Dịch vụ AI quá thời gian chờ.'));
      }, milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}
function createApp({ providers = createProviders(), deadlineMs = 75000, rateLimit = 10 } = {}) {
  const app = express(); const windows = new Map();
  app.set('trust proxy', 'loopback'); app.use(cors({ origin: true }));
  function limit(req, res, next) {
    const now = Date.now();
    for (const [key, value] of windows) if (value.until <= now) windows.delete(key);
    const key = req.ip || 'unknown';
    const window = windows.get(key) || { count: 0, until: now + 15 * 60 * 1000 };
    if (window.count >= rateLimit) {
      res.set('Retry-After', String(Math.ceil((window.until - now) / 1000)));
      return next(new ApiError(429, 'rate_limit_exceeded', 'Quá nhiều yêu cầu. Vui lòng thử lại sau.'));
    }
    window.count++; windows.set(key, window); next();
  }
  const asyncRoute = handler => (req, res, next) => Promise.resolve(handler(req, res)).catch(next);
  app.get(['/health', '/api/health'], (_, res) => res.json({ status: 'ok', service: 'MemoMind AI' }));
  const generate = legacy => asyncRoute(async (req, res) => {
    let body = req.body;
    if (legacy) {
      if (!['qa', 'cloze', 'mixed'].includes(body?.format ?? 'mixed')) throw new ApiError(400, 'invalid_request', 'Loại học liệu không hợp lệ.');
      body = { ...body, types: body.format === 'qa' ? ['BASIC'] : body.format === 'cloze' ? ['CLOZE'] : ['BASIC', 'CLOZE'],
        quantityMode: 'manual', desiredCount: body.desiredCount ?? 5,
        sourceBlocks: Array.isArray(body.sourceBlocks) ? body.sourceBlocks.map(b => ({ ...b, documentId: b?.documentId ?? body.documentId })) : body.sourceBlocks };
      if (body.desiredCount === 1 && body.types.length === 2) body.types = ['BASIC'];
    }
    const request = validateRequest(body);
    const rawCards = await withinDeadline(async signal => {
      const first = await providers.generate(request, signal);
      let parsed = parseEnvelope(first);
      if (parsed === null) parsed = parseEnvelope(await providers.generate(request, signal, first));
      if (parsed === null) throw new ApiError(502, 'invalid_llm_output', 'AI trả dữ liệu sai định dạng sau một lần sửa.');
      return parsed;
    }, deadlineMs);
    const result = filterCards(rawCards, request);
    if (!result.cards.length) return res.status(422).json({ ...result, error: 'no_valid_cards', message: 'Không có học liệu đạt kiểm tra nguồn và cấu trúc.' });
    if (legacy) {
      result.cards = result.cards.map(c => ({ type: 'flashcard', format: c.type === 'CLOZE' ? 'cloze' : 'qa',
        question: c.front, answer: c.back, sourceBlockId: c.sourceBlockId, sourcePage: c.sourcePage,
        sourceQuote: c.sourceQuote, confidence: c.confidence }));
      result.warnings = result.warnings.map(w => `${w.code}: ${w.count}`);
    }
    res.json(result);
  });
  app.post(['/api/v1/materials/generate', '/v1/materials/generate'], limit, express.json({ limit: '2mb' }), generate(false));
  app.post(['/api/v1/materials/flashcards/generate', '/v1/materials/flashcards/generate'], limit, express.json({ limit: '2mb' }), generate(true));
  app.post(['/api/v1/ocr/enhance', '/v1/ocr/enhance'], limit, express.json({ limit: '8mb' }), asyncRoute(async (req, res) => {
    const { imageBase64, currentText } = req.body || {};
    if (typeof imageBase64 !== 'string' || !imageBase64.length || imageBase64.length % 4 !== 0 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(imageBase64) ||
        (currentText !== undefined && (typeof currentText !== 'string' || currentText.length > 100000))) {
      throw new ApiError(400, 'invalid_request', 'Ảnh hoặc văn bản OCR không hợp lệ.');
    }
    const bytes = Buffer.from(imageBase64, 'base64');
    if (bytes.length > 5 * 1024 * 1024) throw new ApiError(413, 'payload_too_large', 'Vùng ảnh tối đa 5 MB.');
    if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) {
      throw new ApiError(400, 'invalid_request', 'Cần ảnh JPEG hợp lệ.');
    }
    res.json(await withinDeadline(signal => providers.enhance(req.body, signal), deadlineMs));
  }));
  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);
    const status = error instanceof ApiError ? error.status : error.type === 'entity.too.large' ? 413 : error.type === 'entity.parse.failed' ? 400 : 500;
    res.status(status).json({ error: error instanceof ApiError ? error.code : (status === 413 ? 'payload_too_large' : status === 400 ? 'invalid_request' : 'server_error'),
      message: error instanceof ApiError ? error.message : status === 413 ? 'Nội dung yêu cầu quá lớn.' : status === 400 ? 'JSON yêu cầu không hợp lệ.' : 'Không thể xử lý yêu cầu lúc này.' });
  });
  return app;
}
module.exports = { createApp, withinDeadline };
