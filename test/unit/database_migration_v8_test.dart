import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'material_generation_database_v6_test.dart' as fixture;

void main() {
  setUpAll(sqfliteFfiInit);
  for (final original in ['v6', 'v7-review', 'v7-merged']) {
    test(
      'upgrade $original preserves sourced cards, schedule and review state',
      () async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(db.close);
        await db.execute('PRAGMA foreign_keys=ON');
        await MemoMindDatabase.createV6(db);
        await fixture.seed(db);
        await db.insert('decks', {
          'deck_id': 'd',
          'title': 'Deck',
          'tone': 'indigo',
          'card_count': 1,
          'created_at': 1,
          'updated_at': 2,
        });
        await db.insert('cards', {
          'card_id': 'c',
          'deck_id': 'd',
          'type': 'BASIC',
          'front': 'Q',
          'back': 'A',
          'source_document_id': 'doc',
          'source_page_id': 'p',
          'source_page_number': 1,
          'source_block_id': 'b',
          'source_quote': 'Văn bản chuẩn',
          'status': 'active',
          'repetitions': 2,
          'interval_days': 6,
          'ease_factor': 2.4,
          'due_date': 1234,
          'created_at': 1,
          'updated_at': 2,
        });
        if (original != 'v6') {
          await MemoMindDatabase.migrateV6ToV7(db);
          if (original == 'v7-review') {
            await db.execute('ALTER TABLE decks DROP COLUMN tags');
            await db.execute('ALTER TABLE decks DROP COLUMN status');
          }
          await db.insert('app_settings', {
            'key': 'device_id',
            'value': 'device',
          });
          await db.insert('review_sessions', {
            'session_id': 's',
            'deck_id': 'd',
            'due_only': 1,
            'queue': '[]',
            'learning_queue': '["c"]',
            'initial_count': 1,
            'status': 'active',
            'created_at': 1,
            'updated_at': 2,
          });
          await db.insert('review_events', {
            'event_id': 'e',
            'session_id': 's',
            'card_id': 'c',
            'device_id': 'device',
            'reviewed_at': 2,
            'rating': 'again',
          });
        }
        await db.transaction((txn) async {
          if (original == 'v6') await MemoMindDatabase.migrateV6ToV7(txn);
          await MemoMindDatabase.migrateV7ToV8(txn);
        });
        final c = (await db.query('cards')).single;
        expect(c['source_quote'], 'Văn bản chuẩn');
        expect(c['repetitions'], 2);
        expect(c['due_date'], 1234);
        expect(c['tags'], '[]');
        expect((await db.query('decks')).single['status'], 'active');
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        if (original != 'v6') {
          expect((await db.query('review_events')).single['event_id'], 'e');
          expect(
            (await db.query('review_sessions')).single['learning_queue'],
            '["c"]',
          );
          expect((await db.query('app_settings')).single['value'], 'device');
        }
      },
    );
  }

  test(
    'migration fails atomically without partially adding deck columns',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await MemoMindDatabase.createV7(db);
      await db.execute('ALTER TABLE decks DROP COLUMN tags');
      await db.execute('ALTER TABLE decks DROP COLUMN status');
      // Inject a corrupt legacy schema to fail after adding columns.
      await db.execute('ALTER TABLE cards RENAME COLUMN front TO broken_front');
      await expectLater(
        db.transaction((txn) => MemoMindDatabase.migrateV7ToV8(txn)),
        throwsA(isA<DatabaseException>()),
      );
      final columns = (await db.rawQuery('PRAGMA table_info(decks)'))
          .map((r) => r['name']);
      expect(columns, isNot(contains('tags')));
      expect(
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE name='cards'"))
            .length,
        1,
      );
    },
  );
}
