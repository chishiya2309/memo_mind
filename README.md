# MemoMind AI

MemoMind AI is an Android-focused Flutter project for turning short lecture documents into source-linked study cards and reviewing them offline. The app currently includes an interactive home screen and an offline-first camera/gallery document-import flow. OCR, Firebase sync, and review sessions are planned, not yet implemented.

## Architecture

- Imported documents and source-page metadata are stored through SQLite (`sqflite`). Future study data will use the same local-first boundary; the UI will not query Firestore as its primary data source.
- Firebase Authentication, Firestore, App Check, and Firebase AI Logic are planned for identity, cloud sync, and AI generation. Firestore will be a cloud replica.
- OCR will run on the device. A user will confirm extracted text and review generated cards before saving them.
- Review events will be immutable. The SM-2 scheduler will belong in pure Dart domain code, independent of Flutter, SQLite, and Firebase.

## Project layout

```text
lib/
  app/                    # App setup, bootstrap, and routing
  core/
    database/migrations/  # SQLite setup and versioned migrations
    firebase/             # Shared Firebase configuration and adapters
    errors/
    logging/
    platform/             # Device and operating-system integrations
  features/
    document_import/
    home/                   # Dashboard UI and sample presentation data
    ocr_editor/
    material_generation/
    deck_management/
    review_session/
    statistics/
    sync/
    backup/               # P1 placeholder
    deck_sharing/         # P1 placeholder
    push_notifications/   # P1 placeholder
  shared/
    widgets/
    theme/
test/
  unit/
  widget/
integration_test/
docs/
  architecture/
  decisions/
firebase/                 # Firebase rules and emulator setup, when added
functions/                # P1 Cloud Functions placeholder
```

Each P0 feature has `presentation`, `application`, `domain`, and `data` directories. Empty directories contain `.gitkeep` so Git can track them. Add a real file to a directory and remove its `.gitkeep` when work begins there.

## Delivery stages

- **P0:** Camera/gallery document import is implemented with private app storage and SQLite metadata. Local deck and card management, on-device OCR and correction, source-linked AI material generation through Firebase AI Logic, offline review, local reminders and statistics remain planned. The `sync` directory reserves the boundary for cloud replication.
- **P1:** Cloud Functions, original-file backup in Cloud Storage, multi-device sync, private deck sharing, and push notifications. The corresponding directories are placeholders only.

## Getting started and collaborating

1. Install the Flutter SDK and Android development tools.
2. Run `flutter pub get` and `flutter run` from this directory. The home screen uses sample data; unfinished destinations are clearly marked.
3. Run `flutter test` and `flutter analyze` before proposing changes.
4. Create a branch from `main` for each change and open a pull request for review. Keep feature code inside its feature directory and record architecture decisions in `docs/decisions`.

Do not commit `.env` files, service-account keys, or other credentials. Firebase project configuration and dependencies will be added when their features are implemented. This repository has no GitHub remote configured yet.

Be Vietnam Pro font files are bundled for offline use. Its license is in `licenses/BeVietnamPro-OFL.txt`.
