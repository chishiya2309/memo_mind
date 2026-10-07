import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/sync/application/sync_controller.dart';
import 'package:memo_mind/features/sync/data/sync_api_client.dart';
import 'package:memo_mind/features/sync/data/local_sync_store.dart';
import 'package:memo_mind/features/account_backup/data/snapshot_codec.dart';

import '../support/account_backup_fakes.dart';

class _Api extends SyncApiClient {
  _Api(FakeAccountAuth auth, String url) : super(auth: auth, baseUrl: url);
  bool loseResponse = false;
  bool loseBeforeRequest = false;
  bool corruptDownload = false;
  Future<void> Function()? duringPush;
  Future<void> Function()? beforeResolution;
  final writes = <Map<String, dynamic>>[];
  @override
  Future<void> download(String url, File file) async {
    if (corruptDownload) {
      corruptDownload = false;
      await file.writeAsBytes([1, 2, 3]);
      return;
    }
    await super.download(url, file);
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, Object?>? body,
    required String uid,
  }) async {
    if (body?['operations'] != null) writes.add({'route': suffix, ...body!});
    if (suffix.endsWith('/resolve')) {
      final action = beforeResolution;
      beforeResolution = null;
      await action?.call();
    }
    if (suffix == '/push' && loseBeforeRequest) {
      loseBeforeRequest = false;
      throw const AccountFailure('unconfirmed', 'Lost response');
    }
    final result = await super.request(method, suffix, body: body, uid: uid);
    if (suffix == '/push' || suffix.endsWith('/resolve')) {
      final action = duringPush;
      duringPush = null;
      await action?.call();
      if (loseResponse) {
        loseResponse = false;
        throw const AccountFailure('unconfirmed', 'Lost response');
      }
    }
    return result;
  }
}

class _Device {
  _Device(this.workspaces, this.auth, this.api);
  final WorkspaceRepository workspaces;
  final FakeAccountAuth auth;
  final _Api api;
  late final sync = SyncController(
    auth: auth,
    workspaces: workspaces,
    api: api,
  );
  WorkspaceContext get context => workspaces.current!;
  LocalSyncStore get local => LocalSyncStore(context);
  void activate(String id) {
    WorkspaceRuntime.current = context;
    WorkspaceRuntime.deviceId = id;
  }

  LocalDeckRepository get decks =>
      LocalDeckRepository(database: context.database);
  LocalReviewRepository get reviews =>
      LocalReviewRepository(database: context.database);
  Future<void> flush(String id) async {
    activate(id);
    await sync.syncNow();
    expect(sync.error, isNull, reason: sync.error);
  }

  Future<void> close() async {
    sync.dispose();
    await auth.updates.close();
    await workspaces.close();
  }
}

void main() {
  late Directory root;
  late Process server;
  late String url;
  final devices = <_Device>[];
  setUpAll(() {
    // The integration server runs on the host; Android connectivity is mocked
    // separately in widget tests and must not require a platform binding here.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-integration-');
    server = await Process.start('node', [
      'test/support/sync_server.cjs',
    ], workingDirectory: Directory.current.path);
    final stderr = StringBuffer();
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    url = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw StateError('Node server: $stderr'),
        );
  });
  tearDown(() async {
    for (final device in devices) {
      await device.close();
    }
    devices.clear();
    server.kill();
    await server.exitCode;
    await root.delete(recursive: true);
  });
  Future<_Device> device(String id) async {
    final workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, id, 'files'),
      databaseRoot: p.join(root.path, id, 'db'),
    );
    await workspaces.initialize();
    await workspaces.select(await workspaces.canonical('A'));
    final auth = FakeAccountAuth(
      identity: const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    final result = _Device(workspaces, auth, _Api(auth, url));
    devices.add(result);
    await result.local.setSetting('migrationAccepted', '1');
    return result;
  }

  Future<(String, String)> seed(_Device a) async {
    a.activate('phone');
    final deck = await a.decks.createDeck(title: 'English');
    final card = await a.decks.createManualCard(
      deckId: deck.id,
      content: const CardContent(
        type: CardType.basic,
        front: 'Hello',
        back: 'Xin chào',
      ),
    );
    await a.flush('phone');
    return (deck.id, card.id);
  }

  test('new device downloads canonical content and progress without selecting a snapshot', () async {
    final a = await device('A');
    final (_, cardId) = await seed(a);
    final session = await a.reviews.startSession();
    await a.reviews.rate(
      sessionId: session!.session.id,
      cardId: cardId,
      eventId: 'event-A',
      reviewedAt: DateTime.utc(2026, 10, 5, 9),
      rating: ReviewRating.good,
    );
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    final row = (await (await b.context.database.database).query('cards'))
        .single;
    expect(row['front'], 'Hello');
    expect(row['repetitions'], 1);
    expect(
      (await (await b.context.database.database).query('review_events')).length,
      1,
    );
    expect(await b.reviews.getActiveSession(), isNull);
    expect(await b.local.hasPending, isFalse);
  });

  test(
    'legacy cloud geometry clears any previous local image binding',
    () async {
      final a = await device('A');
      final db = await a.context.database.database;
      await db.insert('documents', {
        'document_id': 'doc',
        'title': 'Source',
        'status': 'ready_for_generation',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert('source_pages', {
        'page_id': 'page',
        'document_id': 'doc',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'gallery',
        'data_relative_path': 'documents/doc/image.png',
        'mime_type': 'image/png',
        'file_size_bytes': 1,
        'width': 800,
        'height': 1000,
        'sha256': 'a' * 64,
        'quality_code': 'good',
        'quality_warning_accepted': 0,
        'created_at': 1,
      });
      await db.insert('source_blocks', {
        'block_id': 'block',
        'document_id': 'doc',
        'page_id': 'page',
        'page_number': 1,
        'order_index': 0,
        'raw_text': 'Source',
        'normalized_text': 'Source',
        'box_left': .1,
        'box_top': .1,
        'box_width': .6,
        'box_height': .2,
        'has_valid_box': 1,
        'box_image_sha256': 'a' * 64,
        'confidence_source': 'unavailable',
        'status': 'draft',
        'created_at': 1,
        'updated_at': 1,
      });
      final legacy =
          Map<String, dynamic>.from((await db.query('source_blocks')).single)
            ..remove('box_image_sha256')
            ..['box_top'] = .5;
      await db.delete(
        'sync_outbox',
        where: 'table_name=?',
        whereArgs: ['source_blocks'],
      );
      await a.local.applyChanges({
        'changes': [
          {
            'table': 'source_blocks',
            'entityId': 'block',
            'data': legacy,
            'version': 1,
            'deleted': false,
            'groupEnd': true,
          },
        ],
      });
      final received = (await db.query('source_blocks')).single;
      expect(received['box_top'], .5);
      expect(received['box_image_sha256'], isNull);
      await a.local.materializeMirrors();
      expect(
        (await db.query('source_blocks')).single['box_image_sha256'],
        isNull,
      );
    },
  );

  test('explicit missing_parent recovers local parent and then sends the frozen children', () async {
    final a = await device('A');
    a.activate('phone');
    final deck = await a.decks.createDeck(title: 'Recover parent');
    final card = await a.decks.createManualCard(
      deckId: deck.id,
      content: const CardContent(type: CardType.basic, front: 'Q', back: 'A'),
    );
    final db = await a.context.database.database;
    final deckRow = (await db.query('decks')).single;
    await db.delete('sync_outbox', where: 'table_name=?', whereArgs: ['decks']);
    // A stale mirror falsely says the parent exists; the real backend rejects it.
    await db.insert('sync_meta', {
      'table_name': 'decks',
      'entity_id': deck.id,
      'version': 1,
      'data': jsonEncode(wireRow('decks', deckRow)),
      'deleted': 0,
    });
    final frozen = await a.local.nextPacket('phone');
    expect(
      (frozen!.body['operations'] as List).any((op) => op['table'] == 'decks'),
      isFalse,
    );
    await a.flush('phone');
    expect(a.api.writes.length, greaterThanOrEqualTo(2));
    expect(await a.local.hasPending, isFalse);
    final b = await device('B');
    await b.flush('tablet');
    expect((await b.decks.getDecks()).single.id, deck.id);
    expect((await b.decks.getCardsForDeck(deck.id)).single.id, card.id);
  });

  test(
    'first sync removes an orphan schedule and keeps eight offline cards',
    () async {
      final a = await device('A');
      a.activate('phone');
      final deck = await a.decks.createDeck(title: 'Offline');
      final ids = <String>[];
      for (var i = 0; i < 8; i++) {
        ids.add(
          (await a.decks.createManualCard(
            deckId: deck.id,
            content: CardContent(
              type: CardType.basic,
              front: 'Q$i',
              back: 'A$i',
            ),
          )).id,
        );
      }
      final db = await a.context.database.database;
      await a.context.database.studyTransaction(
        (txn) => txn.insert('card_schedules', {
          'card_id': 'ghost-card',
          'repetitions': 1,
          'interval_days': 1,
          'ease_factor': 2.5,
          'due_date': 1,
          'reviewed_at': 1,
          'device_id': 'phone',
          'event_id': 'ghost-review',
          'scheduler_version': 'sm2-v1',
        }),
      );
      // Stale local metadata makes the first packet reach the backend, which
      // explicitly rejects it as missing_parent.
      await db.insert('sync_meta', {
        'table_name': 'cards',
        'entity_id': 'ghost-card',
        'version': 1,
        'data': '{}',
        'deleted': 0,
      });
      await db.insert('sync_meta', {
        'table_name': 'card_schedules',
        'entity_id': 'ghost-card',
        'version': 5,
        'data': jsonEncode(
          (await db.query(
            'card_schedules',
            where: 'card_id=?',
            whereArgs: ['ghost-card'],
          )).single,
        ),
        'deleted': 0,
      });
      await a.flush('phone');
      expect((await db.query('cards')).length, 8);
      expect(
        await db.query(
          'card_schedules',
          where: 'card_id=?',
          whereArgs: ['ghost-card'],
        ),
        isEmpty,
      );
      expect((await a.local.cleanupReport()).total, 1);
      expect(a.sync.cleanupReport.total, 1);
      expect(await a.local.hasPending, isFalse);
      final b = await device('B');
      await b.flush('tablet');
      final received = await b.decks.getCardsForDeck(deck.id);
      expect(received.map((card) => card.id).toSet(), ids.toSet());
      await a.flush('phone');
      expect((await a.local.cleanupReport()).total, 1);
    },
  );

  test(
    'guest offline cards import into a new account despite an orphan schedule',
    () async {
      final a = await device('A');
      final guest = await a.workspaces.create(null);
      await a.workspaces.select(guest);
      a.activate('phone');
      final deck = await a.decks.createDeck(title: 'Guest lessons');
      for (var i = 0; i < 8; i++) {
        await a.decks.createManualCard(
          deckId: deck.id,
          content: CardContent(
            type: CardType.basic,
            front: 'Guest Q$i',
            back: 'Guest A$i',
          ),
        );
      }
      await a.context.database.studyTransaction(
        (txn) => txn.insert('card_schedules', {
          'card_id': 'guest-orphan',
          'repetitions': 1,
          'interval_days': 1,
          'ease_factor': 2.5,
          'due_date': 1,
          'reviewed_at': 1,
          'device_id': 'phone',
          'event_id': 'guest-review',
          'scheduler_version': 'sm2-v1',
        }),
      );
      final canonical = await a.sync.prepareAccount(guest: guest);
      await a.workspaces.select(canonical);
      await a.flush('phone');
      expect((await a.local.cleanupReport()).total, 1);
      expect((await a.decks.getCardsForDeck(deck.id)).length, 8);
      final b = await device('B');
      await b.flush('tablet');
      expect((await b.decks.getCardsForDeck(deck.id)).length, 8);
    },
  );

  test(
    'unknown result keeps a frozen orphan packet until a confirmed rejection',
    () async {
      final a = await device('A');
      a.activate('phone');
      final db = await a.context.database.database;
      await a.context.database.studyTransaction(
        (txn) => txn.insert('card_schedules', {
          'card_id': 'missing-card',
          'repetitions': 1,
          'interval_days': 1,
          'ease_factor': 2.5,
          'due_date': 1,
          'reviewed_at': 1,
          'device_id': 'phone',
          'event_id': 'missing-review',
          'scheduler_version': 'sm2-v1',
        }),
      );
      await db.insert('sync_meta', {
        'table_name': 'cards',
        'entity_id': 'missing-card',
        'version': 1,
        'data': '{}',
        'deleted': 0,
      });
      final frozen = await a.local.nextPacket('phone');
      a.api.loseBeforeRequest = true;
      await a.sync.syncNow();
      expect(a.sync.failureCode, 'unconfirmed');
      expect((await a.local.cleanupReport()).total, 0);
      expect((await a.local.nextPacket('phone'))!.body, frozen!.body);
      await a.flush('phone');
      expect((await a.local.cleanupReport()).total, 1);
      expect(await a.local.hasPending, isFalse);
    },
  );

  test(
    'a stale capture is removed without deleting its now-valid card',
    () async {
      final a = await device('A');
      a.activate('phone');
      final deck = await a.decks.createDeck(title: 'Healthy');
      final card = await a.decks.createManualCard(
        deckId: deck.id,
        content: const CardContent(type: CardType.basic, front: 'Q', back: 'A'),
      );
      final db = await a.context.database.database;
      final row = (await db.query(
        'cards',
        where: 'card_id=?',
        whereArgs: [card.id],
      )).single;
      await db.delete(
        'sync_outbox',
        where: 'table_name=? AND entity_id=?',
        whereArgs: ['cards', card.id],
      );
      await db.insert('sync_outbox', {
        'table_name': 'cards',
        'entity_id': card.id,
        'group_id': 'stale-group',
        'operation_id': 'stale-op',
        'base_version': 0,
        'before_data': null,
        'data': jsonEncode({...row, 'deck_id': 'missing-deck'}),
        'deleted': 0,
      });
      await a.flush('phone');
      expect(
        (await db.query(
          'cards',
          where: 'card_id=?',
          whereArgs: [card.id],
        )).single['deck_id'],
        deck.id,
      );
      expect((await a.local.cleanupReport()).total, 1);
      final b = await device('B');
      await b.flush('tablet');
      expect((await b.decks.getCardsForDeck(deck.id)).single.id, card.id);
    },
  );

  test(
    'staged transaction retries valid cards after rejecting an orphan',
    () async {
      final a = await device('A');
      a.activate('phone');
      final deck = await a.decks.createDeck(title: 'Large offline deck');
      final db = await a.context.database.database;
      await a.context.database.studyTransaction((txn) async {
        for (var i = 0; i < 51; i++) {
          await txn.insert('cards', {
            'card_id': 'large-$i',
            'deck_id': deck.id,
            'type': 'BASIC',
            'status': 'active',
            'front': 'Q$i',
            'back': 'A$i',
            'due_date': 1,
            'created_at': 1,
            'updated_at': 1,
          });
        }
        await txn.insert('card_schedules', {
          'card_id': 'staged-ghost',
          'repetitions': 1,
          'interval_days': 1,
          'ease_factor': 2.5,
          'due_date': 1,
          'reviewed_at': 1,
          'device_id': 'phone',
          'event_id': 'staged-ghost-event',
          'scheduler_version': 'sm2-v1',
        });
      });
      await db.insert('sync_meta', {
        'table_name': 'cards',
        'entity_id': 'staged-ghost',
        'version': 1,
        'data': '{}',
        'deleted': 0,
      });
      await a.flush('phone');
      expect(a.api.writes.any((write) => write['route'] == '/stage'), isTrue);
      expect((await db.query('cards')).length, 51);
      expect((await a.local.cleanupReport()).total, 1);
      final b = await device('B');
      await b.flush('tablet');
      expect((await b.decks.getCardsForDeck(deck.id)).length, 51);
    },
  );

  test('missing local parent discards only required children and never resurrects a deleted deck', () async {
    final a = await device('A');
    a.activate('phone');
    final deck = await a.decks.createDeck(title: 'Deleted parent');
    await a.decks.createManualCard(
      deckId: deck.id,
      content: const CardContent(type: CardType.basic, front: 'Q', back: 'A'),
    );
    final db = await a.context.database.database;
    await db.update('sync_control', {'applying': 1}, where: 'id=1');
    await db.update(
      'decks',
      {'status': 'deleted'},
      where: 'deck_id=?',
      whereArgs: [deck.id],
    );
    await db.update('sync_control', {'applying': 0}, where: 'id=1');
    await db.delete('sync_outbox', where: 'table_name=?', whereArgs: ['decks']);
    await a.sync.syncNow();
    expect(a.sync.error, isNull);
    expect(await a.local.hasPending, isFalse);
    expect((await db.query('decks')).single['status'], 'deleted');
    expect(await db.query('cards'), isEmpty);
    expect((await a.local.cleanupReport()).total, 2);
    expect(a.api.writes, isEmpty);
  });

  test('packet includes an unseen parent from a later transaction across the 50-row limit', () async {
    final a = await device('A');
    a.activate('phone');
    final deck = await a.decks.createDeck(title: 'Delayed parent');
    final db = await a.context.database.database;
    await db.delete('sync_outbox', where: 'table_name=?', whereArgs: ['decks']);
    await a.context.database.studyTransaction((txn) async {
      for (var i = 0; i < 51; i++) {
        await txn.insert('cards', {
          'card_id': 'dependent-$i',
          'deck_id': deck.id,
          'type': 'BASIC',
          'status': 'active',
          'front': 'Q$i',
          'back': 'A$i',
          'due_date': 1,
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });
    await a.decks.updateDeck(deck.id, title: 'Parent arrives later');
    await a.flush('phone');
    expect(a.api.writes.where((p) => p['route'] == '/stage'), isNotEmpty);
    final b = await device('B');
    await b.flush('tablet');
    expect((await b.decks.getCardsForDeck(deck.id)).length, 51);
    expect(await b.local.hasPending, isFalse);
  });

  test('offline reviews and card edits converge independently, preserving both review events', () async {
    final a = await device('A');
    final (_, cardId) = await seed(a);
    final b = await device('B');
    await b.flush('tablet');
    a.activate('phone');
    final sa = await a.reviews.startSession();
    await a.reviews.rate(
      sessionId: sa!.session.id,
      cardId: cardId,
      eventId: 'event-A',
      reviewedAt: DateTime.utc(2026, 10, 5, 9),
      rating: ReviewRating.good,
    );
    b.activate('tablet');
    final sb = await b.reviews.startSession();
    await b.reviews.rate(
      sessionId: sb!.session.id,
      cardId: cardId,
      eventId: 'event-B',
      reviewedAt: DateTime.utc(2026, 10, 5, 10),
      rating: ReviewRating.easy,
    );
    await b.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'Hello!',
        back: 'Xin chào!',
      ),
    );
    await a.flush('phone');
    await b.flush('tablet');
    await a.flush('phone');
    for (final d in [a, b]) {
      final db = await d.context.database.database;
      expect((await db.query('review_events')).length, 2);
      expect((await db.query('cards')).single['front'], 'Hello!');
      expect((await db.query('card_schedules')).single['event_id'], 'event-B');
      expect(d.sync.conflicts, isEmpty);
    }
  });

  test('lost commit response retries identical payload and edits made during sending survive', () async {
    final a = await device('A');
    final (deckId, _) = await seed(a);
    await a.decks.updateDeck(deckId, title: 'First');
    a.api.loseResponse = true;
    await a.sync.syncNow();
    expect(a.sync.error, isNotNull);
    expect(await a.local.hasPending, isTrue);
    final frozen = await a.local.nextPacket('phone');
    expect(frozen, isNotNull);
    await a.context.database.close();
    expect((await a.local.nextPacket('phone'))!.body, frozen!.body);
    a.api.duringPush = () async {
      await a.decks.updateDeck(deckId, title: 'Second');
    };
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    expect((await b.decks.getDecks()).single.title, 'Second');
    expect(a.sync.conflicts, isEmpty);
    expect(await a.local.hasPending, isFalse);
  });

  test('concurrent content edits remain recoverable and resolving them updates both devices', () async {
    final a = await device('A');
    final (_, cardId) = await seed(a);
    final b = await device('B');
    await b.flush('tablet');
    await a.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'A question',
        back: 'A answer',
      ),
    );
    await b.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'B question',
        back: 'B answer',
      ),
    );
    await a.flush('phone');
    await b.flush('tablet');
    expect(b.sync.conflicts.length, 1);
    final conflict = b.sync.conflicts.single;
    b.api.loseResponse = true;
    await b.sync.resolve(
      conflict,
      Map<String, dynamic>.from(conflict['local'] as Map),
    );
    expect(await b.local.hasPending, isTrue);
    await b.flush('tablet');
    await a.flush('phone');
    expect(
      (await (await a.context.database.database).query('cards'))
          .single['front'],
      'B question',
    );
    expect(a.sync.conflicts, isEmpty);
  });

  test('large study transaction stages bounded requests and becomes visible atomically across pull pages', () async {
    final a = await device('A');
    final (deckId, _) = await seed(a);
    final template = (await (await a.context.database.database).query('cards'))
        .single;
    await a.context.database.studyTransaction((txn) async {
      for (var i = 0; i < 120; i++) {
        await txn.insert('cards', {
          ...template,
          'card_id': 'bulk-$i',
          'deck_id': deckId,
        });
      }
    });
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    expect(
      (await (await b.context.database.database).query('cards')).length,
      121,
    );
    expect(
      (await (await b.context.database.database).query('sync_inbox')),
      isEmpty,
    );
    expect(await b.local.hasPending, isFalse);
  });

  test('failed local transaction leaves no outbox records and guest import is idempotent', () async {
    final a = await device('A');
    await seed(a);
    final db = await a.context.database.database;
    await expectLater(
      a.context.database.studyTransaction((txn) async {
        await txn.update('decks', {'title': 'Rolled back'});
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await a.local.hasPending, isFalse);
    final guest = await a.workspaces.create(null);
    final source = WorkspaceContext(guest, -9);
    try {
      await LocalDeckRepository(database: source.database)
          .createDeck(title: 'Guest');
      await a.local.importWorkspace(source);
      await a.local.importWorkspace(source);
      expect((await a.decks.getDecks()).length, 2);
      expect((await db.query('sync_imports')).length, 1);
    } finally {
      await source.revoke();
    }
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    expect((await b.decks.getDecks()).length, 2);
  });

  test('media uploads once, downloads with checksum, and source deletion reaches the other device', () async {
    final a = await device('A');
    await seed(a);
    final bytes = utf8.encode('test source bytes');
    final file = File(
      p.join(a.context.record.filesPath, 'documents', 'doc', 'image.png'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    await file.copy(p.join(file.parent.path, 'normalized.png'));
    await a.context.database.studyTransaction((txn) async {
      await txn.insert('documents', {
        'document_id': 'doc',
        'title': 'Source',
        'status': 'pending_ocr',
        'page_count': 1,
        'created_at': 1,
        'updated_at': 1,
      });
      await txn.insert('source_pages', {
        'page_id': 'page',
        'document_id': 'doc',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'gallery',
        'data_relative_path': 'documents/doc/image.png',
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
      await txn.insert('page_normalizations', {
        'page_id': 'page',
        'revision': 1,
        'normalized_relative_path': 'documents/doc/normalized.png',
        'mime_type': 'image/png',
        'file_size_bytes': bytes.length,
        'width': 2,
        'height': 2,
        'sha256': contentHash(bytes),
        'top_left_x': 0.0,
        'top_left_y': 0.0,
        'top_right_x': 1.0,
        'top_right_y': 0.0,
        'bottom_right_x': 1.0,
        'bottom_right_y': 1.0,
        'bottom_left_x': 0.0,
        'bottom_left_y': 1.0,
        'rotation_degrees': 0,
        'contrast': 0.0,
        'updated_at': 1,
      });
      await txn.insert('ocr_page_results', {
        'page_id': 'page',
        'document_id': 'doc',
        'status': 'not_started',
        'raw_full_text': null,
        'updated_at': 1,
      });
      await txn.insert('source_blocks', {
        'block_id': 'block',
        'page_id': 'page',
        'document_id': 'doc',
        'page_number': 1,
        'order_index': 0,
        'raw_text': 'Source text',
        'normalized_text': 'Source text',
        'has_valid_box': 0,
        'confidence_source': 'unavailable',
        'status': 'draft',
        'created_at': 1,
        'updated_at': 1,
      });
    });
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    final downloaded = File(
      p.join(b.context.record.filesPath, 'documents', 'doc', 'image.png'),
    );
    expect(await downloaded.readAsBytes(), bytes);
    final receivedDb = await b.context.database.database;
    expect(
      (await receivedDb.query('ocr_page_results')).single['raw_full_text'],
      isNull,
    );
    expect(
      (await receivedDb.query('source_blocks')).single['normalized_text'],
      'Source text',
    );
    expect(
      (await receivedDb.query('page_normalizations')).single['revision'],
      1,
    );
    expect(await b.local.setting('uploaded.${contentHash(bytes)}'), '1');
    await downloaded.delete();
    b.api.corruptDownload = true;
    await b.sync.syncNow();
    expect(b.sync.error, contains('bị hỏng'));
    expect(b.sync.mediaStatus, isNotNull);
    expect(b.sync.lastSynced, isNotNull);
    expect(await b.sync.hasPending, isTrue);
    await b.sync.bind();
    expect(b.sync.mediaPhase, SyncMediaPhase.pending);
    expect((await b.decks.getDecks()).length, 1);
    await b.flush('tablet');
    expect(b.sync.mediaPhase, SyncMediaPhase.idle);
    expect(await b.local.setting('mediaPending'), '0');
    expect(await downloaded.readAsBytes(), bytes);
    await a.context.database.studyTransaction(
      (txn) =>
          txn.delete('documents', where: 'document_id=?', whereArgs: ['doc']),
    );
    await a.flush('phone');
    await b.flush('tablet');
    expect(
      await (await b.context.database.database).query('source_pages'),
      isEmpty,
    );
    expect(
      await (await b.context.database.database).query('documents'),
      isEmpty,
    );
  });

  test('batching offline reviews keeps the latest timestamp when the clock moves backwards', () async {
    final a = await device('A');
    final (_, cardId) = await seed(a);
    final first = (await a.reviews.startSession())!;
    await a.reviews.rate(
      sessionId: first.session.id,
      cardId: cardId,
      eventId: 'newest-local',
      reviewedAt: DateTime.utc(2026, 10, 5, 10),
      rating: ReviewRating.good,
    );
    final second = (await a.reviews.startSession(dueOnly: false))!;
    await a.reviews.rate(
      sessionId: second.session.id,
      cardId: cardId,
      eventId: 'clock-moved-back',
      reviewedAt: DateTime.utc(2026, 10, 5, 9),
      rating: ReviewRating.hard,
    );
    await a.flush('phone');
    final b = await device('B');
    await b.flush('tablet');
    for (final d in [a, b]) {
      final db = await d.context.database.database;
      expect((await db.query('review_events')).length, 2);
      expect(
        (await db.query('card_schedules')).single['event_id'],
        'newest-local',
      );
      expect((await db.query('cards')).single['repetitions'], 1);
    }
  });
  test(
    'repeating sync without changes does not create another study revision',
    () async {
      final a = await device('A');
      await seed(a);
      final db = await a.context.database.database;
      final revision = (await db.query('workspace_revision'))
          .single['revision'];
      await a.flush('phone');
      await a.flush('phone');
      expect(
        (await db.query('workspace_revision')).single['revision'],
        revision,
      );
      expect(await a.local.hasPending, isFalse);
    },
  );

  test('restore batches content with its baseline and later normal edits retain their normal semantics', () async {
    final a = await device('A');
    final (deckId, cardId) = await seed(a);
    final archived = await a.workspaces.create('A');
    final source = WorkspaceContext(archived, -14);
    try {
      await LocalSyncStore(source).importWorkspace(a.context);
      final session = (await a.reviews.startSession())!;
      await a.reviews.rate(
        sessionId: session.session.id,
        cardId: cardId,
        eventId: 'before-restore',
        reviewedAt: DateTime.utc(2026, 10, 5, 10),
        rating: ReviewRating.good,
      );
      await a.decks.updateCard(
        cardId,
        content: const CardContent(
          type: CardType.basic,
          front: 'Changed later',
          back: 'Answer',
        ),
      );
      await a.flush('phone');
      await a.local.setSetting('restoring', '1');
      await a.local.importWorkspace(source, replace: true);
      await a.decks.updateDeck(deckId, title: 'Normal edit after restore');
      a.api.writes.clear();
      await a.flush('phone');
      final restores = a.api.writes
          .where((p) => p['route'] == '/restore')
          .toList();
      expect(restores, isNotEmpty);
      expect(
        (restores.first['operations'] as List).any(
          (op) => op['table'] == 'cards',
        ),
        isTrue,
      );
      expect(
        (restores.first['operations'] as List).any(
          (op) => op['table'] == 'card_schedules',
        ),
        isTrue,
      );
      expect(
        a.api.writes.any(
          (p) =>
              p['route'] == '/push' &&
              (p['operations'] as List).any(
                (op) => op['data']['title'] == 'Normal edit after restore',
              ),
        ),
        isTrue,
      );
      final b = await device('B');
      await b.flush('tablet');
      final row = (await (await b.context.database.database).query('cards'))
          .single;
      expect(row['front'], 'Hello');
      expect(row['repetitions'], 0);
      expect(
        (await b.decks.getDecks()).single.title,
        'Normal edit after restore',
      );
      expect(
        (await (await b.context.database.database).query('review_events'))
            .length,
        1,
      );
    } finally {
      await source.revoke();
    }
  });

  test('delete and offline edit preserve the edited variant without resurrecting the card', () async {
    final a = await device('A');
    final (_, cardId) = await seed(a);
    final b = await device('B');
    await b.flush('tablet');
    await a.decks.deleteCard(cardId);
    await b.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'Offline edit',
        back: 'Answer',
      ),
    );
    await a.flush('phone');
    await b.flush('tablet');
    await a.flush('phone');
    for (final d in [a, b]) {
      expect(
        (await (await d.context.database.database).query('cards'))
            .single['status'],
        'deleted',
      );
      expect(d.sync.conflicts.single['local']['data']['front'], 'Offline edit');
    }
    final conflict = b.sync.conflicts.single;
    await b.sync.resolve(
      conflict,
      Map<String, dynamic>.from(conflict['local'] as Map),
    );
    await a.flush('phone');
    expect(
      (await (await a.context.database.database).query('cards'))
          .single['front'],
      'Offline edit',
    );
    expect(
      (await (await a.context.database.database).query('cards'))
          .single['status'],
      'active',
    );
  });

  test('a stale resolution retains its chosen content and does not block unrelated changes', () async {
    final a = await device('A');
    final (deckId, cardId) = await seed(a);
    final b = await device('B');
    await b.flush('tablet');
    await a.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'A question',
        back: 'A answer',
      ),
    );
    await b.decks.updateCard(
      cardId,
      content: const CardContent(
        type: CardType.basic,
        front: 'B question',
        back: 'B answer',
      ),
    );
    await a.flush('phone');
    await b.flush('tablet');
    final conflict = b.sync.conflicts.single;
    b.api.beforeResolution = () async {
      await a.decks.updateCard(
        cardId,
        content: const CardContent(
          type: CardType.basic,
          front: 'New A question',
          back: 'New A answer',
        ),
      );
      await a.flush('phone');
    };
    await b.decks.updateDeck(deckId, title: 'Unrelated change');
    b.activate('tablet');
    await b.sync.resolve(
      conflict,
      Map<String, dynamic>.from(conflict['local'] as Map),
    );
    expect(b.sync.error, isNull);
    expect(await b.local.hasPending, isFalse);
    expect(
      b.sync.conflicts.any((c) => c['local']['data']['front'] == 'B question'),
      isTrue,
    );
    await a.flush('phone');
    expect((await a.decks.getDecks()).single.title, 'Unrelated change');
    expect(
      (await (await a.context.database.database).query('cards'))
          .single['front'],
      'New A question',
    );
  });

  test('initial migration requires choosing a legacy source and never guesses the newest empty library', () async {
    final a = await device('A');
    await a.local.setSetting('migrationAccepted', '0');
    final canonical = a.context.record;
    final source = await a.workspaces.create('A', name: 'Currently studying');
    await a.workspaces.select(source);
    a.activate('phone');
    await a.decks.createDeck(title: 'Preserved lessons');
    final empty = await a.workspaces.create('A', name: 'Newer empty restore');
    await a.workspaces.select(empty);
    final chosen = await a.sync.prepareAccount();
    expect(chosen.id, canonical.id);
    expect(a.sync.needsMigration, isFalse);
    await a.workspaces.select(chosen);
    await a.sync.syncNow();
    expect(a.sync.needsMigration, isTrue);
    expect(await a.decks.getDecks(), isEmpty);
    await a.sync.acceptMigration(source: source);
    expect(a.sync.error, isNull);
    final b = await device('B');
    await b.flush('tablet');
    expect((await b.decks.getDecks()).single.title, 'Preserved lessons');
    final legacy = WorkspaceContext(source, -13);
    try {
      expect(
        (await LocalDeckRepository(
          database: legacy.database,
        ).getDecks()).single.title,
        'Preserved lessons',
      );
    } finally {
      await legacy.revoke();
    }
  });

  test(
    'an initialized library always wins over a selected legacy empty workspace',
    () async {
      final a = await device('A');
      await seed(a);
      final canonical = a.context.record;
      await a.workspaces.select(
        await a.workspaces.create('A', name: 'New empty snapshot'),
      );
      final chosen = await a.sync.prepareAccount();
      expect(chosen.id, canonical.id);
      expect(a.sync.needsMigration, isFalse);
      await a.workspaces.select(chosen);
      await a.flush('phone');
      expect((await a.decks.getDecks()).single.title, 'English');
    },
  );

  test('changing UID while awaiting a response never applies account A data to account B', () async {
    final a = await device('A');
    final (deckId, _) = await seed(a);
    await a.decks.updateDeck(deckId, title: 'Pending A');
    a.api.duringPush = () async {
      a.auth.change(
        const AccountIdentity(
          uid: 'B',
          email: 'b@example.com',
          emailVerified: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    };
    await a.sync.syncNow();
    expect(await a.local.hasPending, isTrue);
    final b = await a.workspaces.canonical('B');
    final context = WorkspaceContext(b, -10);
    try {
      expect(await (await context.database.database).query('decks'), isEmpty);
    } finally {
      await context.revoke();
    }
  });
}
