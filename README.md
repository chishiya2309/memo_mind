# MemoMind AI

MemoMind AI is an Android focused Flutter app for turning lecture documents into source cited study cards. It supports offline first camera and gallery import, on device OCR, AI assisted BASIC/CLOZE/MCQ generation, review and correction, and SQLite deck storage.

## Architecture

- Imported pages, confirmed OCR source blocks, decks, and cards are stored in SQLite. Accepted cards retain a document, page, and source block link.
- OCR runs on the device. Optional crop enhancement sends only the selected JPEG region to the Express API after user consent.
- The Express API in `functions/` proxies Groq material generation and Gemini OCR enhancement. Provider API keys stay on the server and never ship in Flutter.
- Offline review uses an SM-2 scheduler. SQLite v7 stores each review event, card schedule, and session progress in one transaction. Cloud sync and cross device replication remain future work.

## Project layout

```text
lib/
  core/database/          # SQLite schema and migrations
  core/network/           # Backend API client
  features/
    document_import/
    ocr_editor/
    material_generation/  # Generate, verify, review, and save source linked materials
    deck_management/
    review/               # Offline review, SM-2, persisted sessions and learning queue
functions/
  src/                    # Express routes, schemas, provider adapters, validators
  test/                   # Provider mocked API tests
test/
  unit/
  widget/
```

## Offline review (UC04–UC05)

On Android, create and save cards through the existing import/OCR/generation flow, then use **Bắt đầu ôn**, **Ôn tự do**, or a deck's review action. Home reads deck and due-card counts from SQLite. An unfinished session exposes **Tiếp tục phiên ôn đang dở**, including when only Again cards remain.

- Only active cards are reviewed. Due sessions select `due_date <= session start`; free review ignores the due date.
- Flip a BASIC, CLOZE, or MCQ card to reveal its answer, then choose Again/Hard/Good/Easy (quality 1/3/4/5).
- Initial schedule: EF 2.5, repetitions 0, interval 0. Successful intervals are 1 day, 6 days, then the previous interval multiplied by the previous EF, rounded to the nearest integer. EF uses `EF + 0.1 - (5-q) * (0.08 + (5-q) * 0.02)`, with a minimum of 1.3.
- Again resets repetitions to 0, sets the long-term interval to 1 day, and queues the card for another attempt at the end of the session. Every subsequent rating also updates the schedule and creates an event.
- Due timestamps are the UTC review time plus the interval in 24-hour days. Home's daily counts use the device's local calendar day.
- Pause/back preserves the session. Completed ratings and queues survive an app restart. Failed writes do not advance the card; retry reuses the same event ID.
- Review history is retained if a card is deleted. Deleted/suspended cards are skipped when resuming. One unfinished session is allowed at a time.
- Review uses no network calls. Web shows an unsupported-platform message because local card storage and OCR are currently Android-focused.

## AI backend setup

1. Install the Flutter SDK and Node.js 18 or newer.
2. In `functions/`, run `npm ci`.
3. Copy `functions/.env.example` to `functions/.env` and set the server secrets `GROQ_API_KEY` and `GEMINI_API_KEY`. Keep both keys off mobile builds and out of source control.
4. Run `npm start` from `functions/`.
5. Configure the app backend URL with `--dart-define=BACKEND_BASE_URL=https://your-api-host`. The default is `https://api.leaselinkconnect.me`.

The backend accepts source materials at `POST /api/v1/materials/generate` and optional OCR crop images at `POST /api/v1/ocr/enhance`. Deploy the backend before using AI from the app. The old flashcard generation endpoint remains available for app compatibility.

Generation requests identify the source document, requested card types, quantity mode, and confirmed source blocks:

```json
{
  "documentId": "document-id",
  "types": ["BASIC", "CLOZE", "MCQ"],
  "quantityMode": "auto",
  "sourceBlocks": [
    {
      "blockId": "source-block-id",
      "documentId": "document-id",
      "pageNumber": 2,
      "normalizedText": "Confirmed text from page two."
    }
  ]
}
```

Use `quantityMode: "manual"` with `desiredCount` from 1–30 to set a total target. Auto mode returns at most 20 cards. The response contains only server validated cards, source links, discard counts, per type counts, and coded warnings. MCQ cards have options A–D, a correct option ID, and an explanation. Requests with no valid result return HTTP 422. The server validates the source blocks supplied with the request; Flutter rechecks them against SQLite before saving.


## Validation

Run `npm test` from `functions/`, and `flutter analyze` plus `flutter test` from the repository root. These checks use mocked provider responses and do not need actual API keys.

Do not commit `.env` files, service account keys, or other credentials. This repository has no GitHub remote configured yet.

Be Vietnam Pro font files are bundled for offline use. Its license is in `licenses/BeVietnamPro-OFL.txt`.
