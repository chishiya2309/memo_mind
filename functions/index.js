/**
 * MemoMind Backend Services - Source-Linked Material Generation (UC07)
 * Adheres to BR07-01 to BR07-18.
 * No client-side LLM API key; API key loaded securely via process.env.
 */

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');

// Tự động nạp file .env khi chạy bằng node index.js mà không cần thư viện ngoài
try {
  const envPath = path.join(__dirname, '.env');
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx > 0) {
        const key = trimmed.slice(0, eqIdx).trim();
        let val = trimmed.slice(eqIdx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        }
        if (!process.env[key]) {
          process.env[key] = val;
        }
      }
    }
  }
} catch (e) {
  console.warn('Lỗi nạp file .env:', e.message);
}

const app = express();
// Trust only the local reverse proxy. This lets the rate limiter see the
// original client IP from Nginx without trusting arbitrary forwarded headers.
app.set('trust proxy', 'loopback');
app.use(cors({ origin: true }));
app.use(express.json({ limit: '2mb' }));

const GROQ_API_KEY = process.env.GROQ_API_KEY || process.env.GEMINI_API_KEY;
const GROQ_MODEL = process.env.GROQ_MODEL || process.env.GEMINI_MODEL || 'openai/gpt-oss-20b';
const MAX_TOTAL_CHARACTERS = 100000; // Limit for a single batch request (Luồng 8a)
const GENERATION_RATE_LIMIT = 10;
const GENERATION_RATE_WINDOW_MS = 15 * 60 * 1000;
const generationRateWindows = new Map();

// A small in-memory fixed-window limiter is sufficient for this single-process
// demo service. For multiple Node workers/instances, use a shared store.
const rateLimitCleanup = setInterval(() => {
  const now = Date.now();
  for (const [ip, window] of generationRateWindows) {
    if (window.expiresAt <= now) generationRateWindows.delete(ip);
  }
}, GENERATION_RATE_WINDOW_MS);
rateLimitCleanup.unref();

function limitGenerationRequests(req, res, next) {
  const now = Date.now();
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  let window = generationRateWindows.get(ip);

  if (!window || window.expiresAt <= now) {
    window = { count: 0, expiresAt: now + GENERATION_RATE_WINDOW_MS };
    generationRateWindows.set(ip, window);
  }

  if (window.count >= GENERATION_RATE_LIMIT) {
    const retryAfterSeconds = Math.max(1, Math.ceil((window.expiresAt - now) / 1000));
    res.set('Retry-After', String(retryAfterSeconds));
    return res.status(429).json({
      error: 'rate_limit_exceeded',
      message: 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.'
    });
  }

  window.count += 1;
  return next();
}

app.get(['/health', '/api/health'], (req, res) => {
  res.json({
    status: 'ok',
    service: 'MemoMind AI Generation Backend (Groq)',
    model: GROQ_MODEL,
    hasApiKey: Boolean(GROQ_API_KEY),
  });
});

/**
 * Normalizes text for substring search (removes extra spaces, punctuation, lowercase)
 */
function normalizeForComparison(str) {
  return (str || '')
    .toLowerCase()
    .replace(/[.,\/#!$%\^&\*;:{}=\-_`~()?"'«»“”]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Verifies if quote is supported by source text (BR07-08)
 */
function isQuoteSupported(quote, sourceText) {
  if (!quote || !sourceText) return false;
  const normQuote = normalizeForComparison(quote);
  const normSource = normalizeForComparison(sourceText);
  if (!normQuote || !normSource) return false;
  return normSource.includes(normQuote);
}

/**
 * Deduplicates cards by question similarity (BR07-17)
 */
function deduplicateCards(cards) {
  const seenQuestions = new Set();
  const result = [];
  for (const card of cards) {
    const normQ = normalizeForComparison(card.question);
    if (!seenQuestions.has(normQ)) {
      seenQuestions.add(normQ);
      result.push(card);
    }
  }
  return result;
}

/**
 * JSON Schema for Groq Structured Output (strict: true)
 * Requires top-level object, additionalProperties: false, and all fields in required array.
 */
const FLASHCARD_RESPONSE_SCHEMA = {
  "type": "object",
  "properties": {
    "cards": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string",
            "enum": ["flashcard"]
          },
          "format": {
            "type": "string",
            "enum": ["qa", "cloze"]
          },
          "question": { "type": "string" },
          "answer": { "type": "string" },
          "sourcePage": { "type": "integer" },
          "sourceBlockId": { "type": "string" },
          "sourceQuote": { "type": "string" },
          "confidence": { "type": "number" }
        },
        "required": [
          "type",
          "format",
          "question",
          "answer",
          "sourcePage",
          "sourceBlockId",
          "sourceQuote",
          "confidence"
        ],
        "additionalProperties": false
      }
    }
  },
  "required": ["cards"],
  "additionalProperties": false
};

/**
 * POST /api/v1/materials/flashcards/generate (also supports /v1/materials/flashcards/generate)
 */
app.post(['/api/v1/materials/flashcards/generate', '/v1/materials/flashcards/generate'], limitGenerationRequests, async (req, res) => {
  if (!GROQ_API_KEY) {
    return res.status(503).json({
      error: 'backend_not_configured',
      message: 'Tính năng AI chưa được cấu hình GROQ_API_KEY trên máy chủ. Vui lòng kiểm tra file .env.'
    });
  }

  const { documentId, format = 'mixed', desiredCount = 5, sourceBlocks } = req.body;

  if (!Array.isArray(sourceBlocks) || sourceBlocks.length === 0) {
    return res.status(400).json({
      error: 'invalid_request',
      message: 'Danh sách SourceBlock không được để trống.'
    });
  }

  // Check total character size (Luồng 8a)
  const totalChars = sourceBlocks.reduce((acc, b) => acc + (b.normalizedText || '').length, 0);
  if (totalChars > MAX_TOTAL_CHARACTERS) {
    return res.status(413).json({
      error: 'payload_too_large',
      message: 'Nội dung được chọn vượt quá giới hạn xử lý một lượt. Vui lòng chọn ít trang hoặc ít khối hơn.'
    });
  }

  // Map of blocks for fast lookup
  const blockMap = new Map();
  for (const block of sourceBlocks) {
    if (block.blockId && block.normalizedText) {
      blockMap.set(block.blockId, block);
    }
  }

  // Construct Prompt
  let formatInstruction = '';
  if (format === 'qa') {
    formatInstruction = 'Chỉ tạo các thẻ dạng hỏi – đáp (format: "qa"). Câu hỏi rõ ràng, đáp án súc tích.';
  } else if (format === 'cloze') {
    formatInstruction = 'Chỉ tạo các thẻ dạng điền khuyết (format: "cloze"). Trong câu hỏi, từ hoặc cụm từ bị khuyết BẮT BUỘC được thay thế bằng ký hiệu "[...]". Trường "answer" là chính từ hoặc cụm từ bị khuyết.';
  } else {
    formatInstruction = 'Tạo kết hợp cả hai loại thẻ: hỏi – đáp (format: "qa") và điền khuyết (format: "cloze", câu hỏi phải có ký hiệu "[...]").';
  }

  const sourceContext = sourceBlocks.map((b, index) => {
    return `[Khối #${index + 1} | blockId: "${b.blockId}" | Trang: ${b.pageNumber}]:\n"${b.normalizedText}"`;
  }).join('\n\n');

  const systemPrompt = `Bạn là trợ lý giáo dục chuyên gia tạo flashcard chất lượng cao từ tài liệu học tập.
Nhiệm vụ: Dựa vào các khối văn bản nguồn được cung cấp, hãy sinh khoảng ${desiredCount} flashcard hữu ích, tập trung vào các khái niệm cốt lõi, định nghĩa, sự kiện hoặc luận điểm quan trọng.

Quy tắc bắt buộc:
1. ${formatInstruction}
2. Mỗi flashcard PHẢI liên kết chính xác với một khối nguồn:
   - "sourceBlockId": PHẢI là một trong các blockId được cung cấp.
   - "sourcePage": Số trang tương ứng của block đó.
   - "sourceQuote": Một đoạn trích dẫn ngắn (10-25 từ) NGUYÊN VĂN từ khối đó làm bằng chứng trực tiếp cho câu hỏi và câu trả lời.
3. KHÔNG bịa đặt thông tin không có trong văn bản nguồn.
4. "confidence": Điền mức độ tự tin (số thực từ 0.8 đến 1.0).
5. "type": Luôn bằng "flashcard".`;

  const requestBody = {
    model: GROQ_MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `Nội dung nguồn tài liệu:\n\n${sourceContext}` }
    ],
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'flashcards_response',
        strict: true,
        schema: FLASHCARD_RESPONSE_SCHEMA
      }
    },
    temperature: 0.2
  };

  try {
    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${GROQ_API_KEY}`
      },
      body: JSON.stringify(requestBody)
    });

    if (response.status === 429) {
      return res.status(429).json({
        error: 'quota_exceeded',
        message: 'Dịch vụ Groq AI tạm thời đã đạt giới hạn sử dụng (rate limit). Vui lòng thử lại sau giây lát.'
      });
    }

    if (response.status === 401) {
      return res.status(503).json({
        error: 'invalid_api_key',
        message: 'GROQ_API_KEY không hợp lệ hoặc đã hết hạn. Vui lòng kiểm tra file .env.'
      });
    }

    if (!response.ok) {
      const errText = await response.text();
      console.error(`Groq API error (${response.status}):`, errText);
      return res.status(502).json({
        error: 'llm_service_error',
        message: `Không thể kết nối hoặc nhận phản hồi từ dịch vụ Groq AI (${response.status}).`
      });
    }

    const data = await response.json();
    const candidateText = data?.choices?.[0]?.message?.content;
    if (!candidateText) {
      return res.status(502).json({
        error: 'empty_llm_response',
        message: 'Không nhận được nội dung sinh từ mô hình AI.'
      });
    }

    let parsedList = [];
    try {
      const parsedData = JSON.parse(candidateText);
      parsedList = Array.isArray(parsedData) ? parsedData : (parsedData.cards || []);
    } catch (e) {
      return res.status(502).json({
        error: 'invalid_json_format',
        message: 'Dịch vụ AI trả về dữ liệu không đúng định dạng JSON yêu cầu.'
      });
    }

    if (!Array.isArray(parsedList)) {
      parsedList = [];
    }

    // Backend Verification Pipeline (BR07-04 -> BR07-08)
    const validCards = [];
    let discardedCount = 0;
    const warnings = [];

    for (const card of parsedList) {
      // BR07-13: question and answer non-empty
      if (!card.question || !card.question.trim() || !card.answer || !card.answer.trim()) {
        discardedCount++;
        warnings.push('Loại bỏ thẻ do câu hỏi hoặc đáp án rỗng.');
        continue;
      }

      // BR07-14: cloze must contain [...]
      if (card.format === 'cloze' && !card.question.includes('[...]')) {
        discardedCount++;
        warnings.push('Loại bỏ thẻ điền khuyết do thiếu ký hiệu vị trí trống [...].');
        continue;
      }

      // BR07-07, 21a: sourceBlockId exists in request
      const matchingBlock = blockMap.get(card.sourceBlockId);
      if (!matchingBlock) {
        discardedCount++;
        warnings.push(`Loại bỏ thẻ do sourceBlockId "${card.sourceBlockId}" không có trong yêu cầu.`);
        continue;
      }

      // Source page consistency
      const expectedPage = matchingBlock.pageNumber;
      if (card.sourcePage !== expectedPage) {
        card.sourcePage = expectedPage; // Correct page number to match block
      }

      // BR07-08, 23a: sourceQuote supported by normalizedText
      if (!isQuoteSupported(card.sourceQuote, matchingBlock.normalizedText)) {
        discardedCount++;
        warnings.push('Loại bỏ thẻ do trích dẫn nguồn không được tìm thấy trong khối văn bản.');
        continue;
      }

      validCards.push(card);
    }

    // BR07-17: Deduplicate
    const finalCards = deduplicateCards(validCards);
    const duplicatesRemoved = validCards.length - finalCards.length;
    discardedCount += duplicatesRemoved;
    if (duplicatesRemoved > 0) {
      warnings.push(`Đã loại bỏ ${duplicatesRemoved} thẻ trùng lặp nội dung.`);
    }

    if (finalCards.length === 0) {
      return res.status(422).json({
        error: 'no_valid_cards',
        message: 'Không có flashcard nào hợp lệ sau khi kiểm tra nguồn và cấu trúc.',
        discardedCount
      });
    }

    return res.json({
      cards: finalCards,
      totalGenerated: parsedList.length,
      validCount: finalCards.length,
      discardedCount,
      warnings
    });
  } catch (err) {
    console.error('Unhandled generation error:', err);
    return res.status(500).json({
      error: 'server_error',
      message: 'Đã xảy ra lỗi nội bộ trong quá trình xử lý học liệu.'
    });
  }
});

const PORT = process.env.PORT || 8080;
const HOST = process.env.HOST || '0.0.0.0';
if (require.main === module) {
  app.listen(PORT, HOST, () => {
    console.log(`MemoMind Backend listening on ${HOST}:${PORT}`);
  });
}

module.exports = app;
