import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/core/workspace/source_file_pins.dart';
import 'package:memo_mind/features/account_backup/data/snapshot_codec.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';

void main() {
  late Directory root;
  late WorkspaceRepository workspaces;
  setUpAll(() {
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fr18-workspaces-');
    workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, 'files'),
      databaseRoot: p.join(root.path, 'databases'),
    );
    await workspaces.initialize();
  });
  tearDown(() async {
    await workspaces.close();
    await root.delete(recursive: true);
  });
  Future<void> attach() async => workspaces.select(
    await workspaces.attach(workspaces.current!.record.id, 'A'),
  );
  Future<void> seed() async {
    final db = await workspaces.current!.database.database;
    final bytes = image.encodePng(image.Image(width: 2, height: 2));
    final file = File(
      p.join(
        workspaces.current!.record.filesPath,
        'documents',
        'doc',
        'page.png',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    await db.insert('documents', {
      'document_id': 'doc',
      'title': 'Source',
      'status': 'ready_for_generation',
      'page_count': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('source_pages', {
      'page_id': 'page',
      'document_id': 'doc',
      'page_number': 1,
      'original_page_number': 1,
      'source': 'gallery',
      'data_relative_path': 'documents/doc/page.png',
      'mime_type': 'image/png',
      'file_size_bytes': bytes.length,
      'width': 2,
      'height': 2,
      'sha256': contentHash(bytes),
      'quality_code': 'good',
      'quality_warning_accepted': 0,
      'created_at': 1,
      'normalization_status': 'source_ready',
    });
    await db.insert('decks', {
      'deck_id': 'deck',
      'title': 'Deck',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('cards', {
      'card_id': 'card',
      'deck_id': 'deck',
      'type': 'MCQ',
      'front': 'Q',
      'back': 'A',
      'mcq_payload': jsonEncode({
        'options': [
          {'optionId': 'A', 'text': 'A'},
          {'optionId': 'B', 'text': 'B'},
          {'optionId': 'C', 'text': 'C'},
          {'optionId': 'D', 'text': 'D'},
        ],
        'correctOptionId': 'A',
        'explanation': 'Why',
      }),
      'source_document_id': 'doc',
      'source_page_id': 'page',
      'source_page_number': 1,
      'source_quote': 'Source',
      'status': 'active',
      'due_date': 100,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('review_sessions', {
      'session_id': 'session',
      'due_only': 1,
      'queue': '[]',
      'learning_queue': '[]',
      'initial_count': 1,
      'status': 'completed',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('review_events', {
      'event_id': 'event',
      'session_id': 'session',
      'card_id': 'card',
      'device_id': 'historical-device',
      'reviewed_at': 100,
      'rating': 'good',
    });
    await db.insert('app_settings', {
      'key': 'secret',
      'value': 'do-not-backup',
    });
  }

  test('legacy is guest; attach and account switches isolate IDs and revoke old repositories', () async {
    final old = LocalDeckRepository();
    await old.createDeck(title: 'Guest deck');
    await attach();
    await expectLater(old.getDecks(), throwsA(isA<StateError>()));
    expect((await LocalDeckRepository().getDecks()).single.title, 'Guest deck');
    final a = workspaces.current!.record;
    await workspaces.select(await workspaces.preferred('B'));
    expect(await LocalDeckRepository().getDecks(), isEmpty);
    expect(workspaces.current!.record.ownerUid, 'B');
    await expectLater(workspaces.attach(a.id, 'B'), throwsA(isA<StateError>()));
    await workspaces.select(await workspaces.preferred(null));
    expect(workspaces.current!.record.ownerUid, isNull);
    expect(await LocalDeckRepository().getDecks(), isEmpty);
    await workspaces.select(a);
    expect((await LocalDeckRepository().getDecks()).single.title, 'Guest deck');
  });
  test(
    'revision updates atomically and rolls back with failed study transaction',
    () async {
      final db = await workspaces.current!.database.database;
      final before = (await db.query('workspace_revision')).single['revision'];
      await expectLater(
        db.transaction((txn) async {
          await txn.insert('decks', {
            'deck_id': 'rollback',
            'title': 'R',
            'created_at': 1,
            'updated_at': 1,
          });
          throw StateError('injected');
        }),
        throwsStateError,
      );
      expect((await db.query('workspace_revision')).single['revision'], before);
      await LocalDeckRepository().createDeck(title: 'Committed');
      expect(
        (await db.query('workspace_revision')).single['revision'],
        greaterThan(before as int),
      );
    },
  );
  test('snapshot round trip retains MCQ/events/IDs and sources, excludes secrets, never replaces current workspace', () async {
    await attach();
    await seed();
    final source = workspaces.current!;
    final codec = SnapshotCodec();
    final snapshot = await codec.capture(source, 'A');
    // Cross-runtime fixture consumed by the Node verifier in the validation run.
    final compatibility = Directory('.dart_tool/fr18');
    await compatibility.create(recursive: true);
    await File(snapshot.path).copy(p.join(compatibility.path, 'snapshot.zip'));
    await File(p.join(compatibility.path, 'snapshot.json'))
        .writeAsString(jsonEncode(snapshot.request));
    final archive = ZipDecoder().decodeBytes(
      await File(snapshot.path).readAsBytes(),
    );
    final json = utf8.decode(archive.find('data.json')!.content);
    expect(json, isNot(contains('do-not-backup')));
    expect(json, isNot(contains('app_settings')));
    expect(archive.find('files/documents/doc/page.png'), isNotNull);
    final restored = await codec.restore(
      File(snapshot.path),
      {...snapshot.request, 'status': 'ready'},
      'A',
      workspaces,
    );
    expect(restored.id, isNot(source.record.id));
    expect(workspaces.current, same(source));
    final imported = MemoMindDatabase.atPath(restored.databasePath);
    final db = await imported.database;
    expect((await db.query('cards')).single['card_id'], 'card');
    expect(
      (await db.query('cards')).single['mcq_payload'],
      contains('correctOptionId'),
    );
    expect(
      (await db.query('review_events')).single['device_id'],
      'historical-device',
    );
    expect((await db.query('review_events')).single['event_id'], 'event');
    expect(
      await File(p.join(restored.filesPath, 'documents', 'doc', 'page.png'))
          .exists(),
      isTrue,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await db.query('app_settings'), isEmpty);
    await imported.close();
  });
  test('same content has stable fingerprint; later review belongs only to next snapshot', () async {
    await attach();
    await seed();
    final codec = SnapshotCodec(), scope = workspaces.current!;
    final first = await codec.capture(scope, 'A'),
        second = await codec.capture(scope, 'A');
    expect(first.request['backupId'], isNot(second.request['backupId']));
    expect(first.request['fingerprint'], second.request['fingerprint']);
    final db = await scope.database.database;
    await db.insert('review_events', {
      'event_id': 'after-t0',
      'session_id': 'session',
      'card_id': 'card',
      'device_id': 'this-device',
      'reviewed_at': 200,
      'rating': 'easy',
    });
    final third = await codec.capture(scope, 'A');
    expect(third.request['fingerprint'], isNot(first.request['fingerprint']));
    expect(
      third.request['snapshotRevision'],
      greaterThan(first.request['snapshotRevision'] as int),
    );
    final old = ZipDecoder().decodeBytes(await File(first.path).readAsBytes());
    expect(
      utf8.decode(old.find('data.json')!.content),
      isNot(contains('after-t0')),
    );
  });
  test('missing/corrupt source and wrong owner/schema/checksum fail without exposing a new workspace', () async {
    await attach();
    await seed();
    final codec = SnapshotCodec(), scope = workspaces.current!;
    final snapshot = await codec.capture(scope, 'A');
    final count = (await workspaces.available('A')).length;
    for (final change in [
      {'ownerUid': 'B'},
      {'schemaVersion': 8},
      {'bundleHash': '0' * 64},
    ]) {
      await expectLater(
        codec.restore(
          File(snapshot.path),
          {...snapshot.request, ...change, 'status': 'ready'},
          'A',
          workspaces,
        ),
        throwsA(isA<AccountFailure>()),
      );
    }
    expect((await workspaces.available('A')).length, count);
    expect(workspaces.current, same(scope));
    final source = File(
      p.join(scope.record.filesPath, 'documents', 'doc', 'page.png'),
    );
    await source.writeAsBytes([1, 2, 3]);
    await expectLater(
      codec.capture(scope, 'A'),
      throwsA(isA<AccountFailure>()),
    );
    await source.delete();
    await expectLater(
      codec.capture(scope, 'A'),
      throwsA(isA<AccountFailure>()),
    );
  });
  test('pinned source deletion waits for snapshot release', () async {
    final file = File(p.join(root.path, 'pinned'))..writeAsStringSync('source');
    SourceFilePins.pin(file.path);
    await SourceFilePins.delete(file);
    expect(await file.exists(), isTrue);
    await SourceFilePins.release(file.path);
    expect(await file.exists(), isFalse);
  });
  test('v8 upgrade preserves legacy data and device identity', () async {
    final legacyRoot = p.join(root.path, 'migration');
    await Directory(legacyRoot).create(recursive: true);
    final old = await databaseFactoryFfi.openDatabase(
      p.join(legacyRoot, 'memo_mind.db'),
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, _) => MemoMindDatabase.createV8(db),
      ),
    );
    await old.insert('decks', {
      'deck_id': 'legacy',
      'title': 'Existing',
      'created_at': 1,
      'updated_at': 1,
    });
    await old.insert('app_settings', {
      'key': 'device_id',
      'value': 'existing-device',
    });
    await old.close();
    final migrated = WorkspaceRepository(
      rootPath: p.join(legacyRoot, 'files'),
      databaseRoot: legacyRoot,
    );
    await migrated.initialize();
    expect((await LocalDeckRepository().getDecks()).single.id, 'legacy');
    expect(WorkspaceRuntime.deviceId, 'existing-device');
    final db = await migrated.current!.database.database;
    expect(await db.getVersion(), 9);
    expect((await db.query('workspace_revision')).single['revision'], 0);
    await migrated.close();
    WorkspaceRuntime.current = workspaces.current;
  });
}
