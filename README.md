# MemoMind AI

MemoMind AI is an Android focused Flutter app for turning lecture documents into source cited study cards. It supports offline first camera and gallery import, on device OCR, AI assisted BASIC/CLOZE/MCQ generation, review and correction, and SQLite deck storage.

## Architecture

- Imported pages, confirmed OCR source blocks, decks, and cards are stored in SQLite. Accepted cards retain a document, page, and source block link.
- OCR runs on the device. Optional crop enhancement sends only the selected JPEG region to the Express API after user consent.
- The Express API in `functions/` proxies Groq material generation and Gemini OCR enhancement. Provider API keys stay on the server and never ship in Flutter.
- Offline review uses an SM-2 scheduler. SQLite v9 adds transactional workspace revisions; each account has an isolated database and source directory. FR18 provides manual backups with Firebase Authentication, Express, Firestore metadata and private Amazon S3 archives. Automatic sync and merging remain outside FR18.

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

On Android, create BASIC/CLOZE/MCQ cards directly in a deck or save accepted cards through the import/OCR/generation flow, then use **Bắt đầu ôn**, **Ôn tự do**, or a deck's review action. Home reads deck and due-card counts from SQLite. An unfinished session exposes **Tiếp tục phiên ôn đang dở**, including when only Again cards remain.

- Only valid active cards in active decks are reviewed. Due sessions select `due_date <= session start`; free review ignores the due date.
- Flip a BASIC, CLOZE, or MCQ card to reveal its answer, then choose Again/Hard/Good/Easy (quality 1/3/4/5).
- Initial schedule: EF 2.5, repetitions 0, interval 0. Successful intervals are 1 day, 6 days, then the previous interval multiplied by the previous EF, rounded to the nearest integer. EF uses `EF + 0.1 - (5-q) * (0.08 + (5-q) * 0.02)`, with a minimum of 1.3.
- Again resets repetitions to 0, sets the long-term interval to 1 day, and queues the card for another attempt at the end of the session. Every subsequent rating also updates the schedule and creates an event.
- Due timestamps are the UTC review time plus the interval in 24-hour days. Home's daily counts use the device's local calendar day.
- Pause/back preserves the session. Completed ratings and queues survive an app restart. Failed writes do not advance the card; retry reuses the same event ID.
- Review history is retained if a card is deleted. Deleted/suspended cards are skipped when resuming. One unfinished session is allowed at a time.
- Review uses no network calls. Web shows an unsupported-platform message because local card storage and OCR are currently Android-focused.

## Due-card reminders (FR16)

On Android, open **Cá nhân → Cài đặt → Nhắc học** to enable reminders and select one local daily time. Reminders default to off and work offline. MemoMind schedules one notification per eligible day within today and the next six calendar days; the window refreshes on startup/resume and committed card/review changes. Notification taps open a freshly queried due-card list. Permission/channel blocking and scheduling errors are shown separately from the saved switch. Android may delay delivery; reopening the app repairs future reminders after clock/timezone changes or force-stop.

See [FR16 validation and device checks](docs/fr16-validation.md) for AC01–AC09 coverage, native integration commands, and the boot receiver compatibility contract.

## Basic learning statistics (FR17)

On Android, **Thống kê** and the home summary share four local SQLite metrics: currently due cards, today's committed review attempts, self-rated success percentage (Hard/Good/Easy), and the current study streak. Multiple ratings of the same card count as separate attempts. Empty history displays a dash for the percentage; ordinary card/deck deletion retains historical attempts.

Statistics refresh after study commits, on returning/resuming, at local midnight and the next due timestamp. Device timezone/clock changes are checked every 30 seconds while visible. Errors retain a prior snapshot with a stale label or show retry; malformed review records are excluded with a warning. No network, login or notification permission is required.

See [FR17 validation and Android checks](docs/fr17-validation.md) for AC01–AC11 coverage and the isolated native integration test.

## Deck management and sources (UC10)

Open **Thư viện** to create, rename, tag, search, or delete a deck. In the deck, add a BASIC, CLOZE, or MCQ card, edit its content/tags, search by content/tags, or review it immediately. Editing an existing card preserves its type, source, schedule, and history. Manual cards have no required source and are immediately due with EF 2.5, repetitions 0, and interval 0.

Deck/card deletion is confirmed and soft: deleted items disappear from the library and review queues while review events and shared source files remain. Failed form saves retain the input and allow retry.

**Xem nguồn** from a saved card or review opens the exact stored source page and quote. Highlighting requires a matching block, a valid finite bounding box, and a decoded image in the correct coordinate system. Missing/corrupt sources retain the quote and stored page number.

Schema v8 migrates both the original review-only v7 and the merged v7 variant with deck tags/status; it preserves schedules, events, session queues, and device IDs. Source references are historical, so source loss cannot cascade-delete cards.

## AI backend setup

1. Install the Flutter SDK and Node.js 22 or newer.
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

Run `npm test` from `functions/`, and `flutter analyze` plus `flutter test` from the repository root. These checks use mocked provider responses and do not need actual API keys. Run Flutter tests before APK builds, sequentially: Flutter regenerates plugin registrants differently for tests/debug and release. Keep the default Pub step when changing build modes (avoid --no-pub for the release build after tests/debug).

```sh
flutter analyze
flutter test --concurrency=1
# With an Android device connected, disable its network for the offline check:
flutter test integration_test/offline_deck_review_test.dart -d DEVICE_ID
# Restore the device network, then build the normal main app:
flutter build apk --debug -t lib/main.dart
flutter build apk --release -t lib/main.dart
```

The integration test uses an isolated temporary database, checks native SQLite persistence after closing/reopening it, and removes its own fixtures. It does not clear the production database. The current Android release configuration uses the development signing key.

See [UC10 / UC04–UC05 validation](docs/uc10-uc04-validation.md) for requirement coverage and the recorded Android checks.

Do not commit `.env` files, service account keys, or other credentials. This repository has no GitHub remote configured yet.

Be Vietnam Pro font files are bundled for offline use. Its license is in `licenses/BeVietnamPro-OFL.txt`.

## Account and manual backups (FR18)

Open **Cá nhân → Cài đặt → Tài khoản và sao lưu**. Firebase Auth supports Google/email, verification, password reset and provider linking. Guest attachment requires a verified account and explicit consent. Logout keeps private workspaces locally and opens a guest workspace. Restoring a verified ready archive creates another workspace and requires confirmation before switching.

Express issues checksum-bound S3 URLs, verifies the complete archive, and commits ready metadata through Firestore transactions. Retry keeps the same frozen snapshot and backup ID. No automatic synchronization or workspace merge is performed.

See [Firebase/S3 setup](docs/deployment/fr18-setup.md) and [FR18 validation](docs/fr18-validation.md). Cloud backup has no default backend URL: configure `config/fr18.local.json` and use `--dart-define-from-file`. Server credentials never belong in this file or an APK.
