const Ajv = require('ajv');
const text = { type: 'string' };
// The provider schema describes shape; local validation also checks business limits.
const cardSchema = {
  type: 'object', additionalProperties: false,
  properties: {
    type: { type: 'string', enum: ['BASIC', 'CLOZE', 'MCQ'] },
    front: text, back: text,
    sourceBlockId: text, sourcePage: { type: 'integer' }, sourceQuote: text,
    confidence: { type: ['number', 'null'] },
    options: { type: ['array', 'null'], items: {
      type: 'object', additionalProperties: false,
      properties: { optionId: { type: 'string', enum: ['A', 'B', 'C', 'D'] }, text },
      required: ['optionId', 'text'],
    } },
    correctOptionId: { type: ['string', 'null'], enum: ['A', 'B', 'C', 'D', null] },
    explanation: { type: ['string', 'null'] },
  },
  required: ['type', 'front', 'back', 'sourceBlockId', 'sourcePage', 'sourceQuote',
    'confidence', 'options', 'correctOptionId', 'explanation'],
};
const responseSchema = {
  type: 'object', additionalProperties: false,
  properties: { cards: { type: 'array', items: cardSchema } }, required: ['cards'],
};
const validateCardSchema = new Ajv({ strict: false }).compile(cardSchema);
module.exports = { responseSchema, validateCardSchema };
