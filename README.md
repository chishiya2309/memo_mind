# MemoMind AI

MemoMind AI is an Android-focused Flutter project for turning short lecture documents into source-linked study cards and reviewing them offline. This repository currently contains the Flutter starter app and a directory scaffold. The features described below are planned, not yet implemented.

## Architecture

- Flutter reads and writes study data through SQLite (`sqflite`). The UI does not query Firestore as its primary data source.
- Firebase Authentication, Firestore, App Check, and Firebase AI Logic support identity, cloud sync, and AI generation. Firestore is a cloud replica; local study and review remain available offline.
- OCR runs on the device. A user confirms the extracted text and reviews generated cards before they are saved.
- Review events are immutable. The SM-2 scheduler belongs in pure Dart domain code, independent of Flutter, SQLite, and Firebase.

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

- **P0:** Local deck and card management, document import, on-device OCR and correction, source-linked AI material generation through Firebase AI Logic, offline review, local reminders and statistics. The `sync` directory reserves the boundary for cloud replication.
- **P1:** Cloud Functions, original-file backup in Cloud Storage, multi-device sync, private deck sharing, and push notifications. The corresponding directories are placeholders only.

## Getting started and collaborating

1. Install the Flutter SDK and Android development tools.
2. Run `flutter pub get` and `flutter run` from this directory. The current app is still the Flutter starter counter screen.
3. Run `flutter test` and `flutter analyze` before proposing changes.
4. Create a branch from `main` for each change and open a pull request for review. Keep feature code inside its feature directory and record architecture decisions in `docs/decisions`.

Do not commit `.env` files, service-account keys, or other credentials. Firebase project configuration and dependencies will be added when their features are implemented. This repository has no GitHub remote configured yet.
