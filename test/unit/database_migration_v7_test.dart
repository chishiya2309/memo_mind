import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('migration V6 -> V7 adds tags and status columns with correct defaults',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    // Create V6 schema (which does NOT have tags/status on decks)
    await MemoMindDatabase.createV6(db);

    // Insert a deck using V6 schema (no tags, no status columns)
    await db.insert('decks', {
      'deck_id': 'deck-v6',
      'title': 'Bộ thẻ Toán',
      'description': 'Ôn thi cuối kỳ',
      'tone': 'teal',
      'card_count': 5,
      'created_at': 100,
      'updated_at': 200,
    });

    // Run migration V6 -> V7
    await MemoMindDatabase.migrateV6ToV7(db);

    // Query the migrated deck
    final decks = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['deck-v6'],
    );
    expect(decks.length, 1);

    final deck = decks.first;

    // Original data preserved
    expect(deck['deck_id'], 'deck-v6');
    expect(deck['title'], 'Bộ thẻ Toán');
    expect(deck['description'], 'Ôn thi cuối kỳ');
    expect(deck['tone'], 'teal');
    expect(deck['card_count'], 5);
    expect(deck['created_at'], 100);
    expect(deck['updated_at'], 200);

    // New columns exist with correct defaults
    expect(deck['tags'], '[]');
    expect(deck['status'], 'active');
  });

  test('migration V6 -> V7 tags column stores valid JSON array', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    await MemoMindDatabase.createV6(db);
    await MemoMindDatabase.migrateV6ToV7(db);

    // Insert a new deck with tags after migration
    final tags = jsonEncode(['java', 'backend', 'spring']);
    await db.insert('decks', {
      'deck_id': 'deck-tagged',
      'title': 'Java Core',
      'tone': 'indigo',
      'card_count': 0,
      'tags': tags,
      'status': 'active',
      'created_at': 300,
      'updated_at': 300,
    });

    final rows = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['deck-tagged'],
    );
    expect(rows.length, 1);
    expect(rows.first['tags'], tags);

    final decoded = jsonDecode(rows.first['tags'] as String) as List;
    expect(decoded, ['java', 'backend', 'spring']);
  });

  test('migration V6 -> V7 status column enforces CHECK constraint',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    await MemoMindDatabase.createV6(db);
    await MemoMindDatabase.migrateV6ToV7(db);

    // 'deleted' should be allowed
    await db.insert('decks', {
      'deck_id': 'deck-deleted',
      'title': 'Xóa rồi',
      'tone': 'indigo',
      'card_count': 0,
      'status': 'deleted',
      'created_at': 400,
      'updated_at': 400,
    });

    final rows = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['deck-deleted'],
    );
    expect(rows.first['status'], 'deleted');

    // Invalid status should fail
    expect(
      () => db.insert('decks', {
        'deck_id': 'deck-invalid',
        'title': 'Sai status',
        'tone': 'indigo',
        'card_count': 0,
        'status': 'archived',
        'created_at': 500,
        'updated_at': 500,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('createV7 produces schema with tags and status columns directly',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    // Create fresh V7 database (as if installing for the first time)
    await MemoMindDatabase.createV7(db);

    // Insert a deck with all V7 columns
    await db.insert('decks', {
      'deck_id': 'deck-fresh',
      'title': 'Bộ thẻ mới',
      'description': 'Tạo trên V7',
      'tone': 'blue',
      'card_count': 0,
      'tags': '["lich-su","on-thi"]',
      'status': 'active',
      'created_at': 600,
      'updated_at': 600,
    });

    final rows = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['deck-fresh'],
    );
    expect(rows.length, 1);
    expect(rows.first['title'], 'Bộ thẻ mới');
    expect(rows.first['tags'], '["lich-su","on-thi"]');
    expect(rows.first['status'], 'active');

    // Default values when tags/status not specified
    await db.insert('decks', {
      'deck_id': 'deck-defaults',
      'title': 'Mặc định',
      'tone': 'amber',
      'card_count': 0,
      'created_at': 700,
      'updated_at': 700,
    });

    final defaults = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['deck-defaults'],
    );
    expect(defaults.first['tags'], '[]');
    expect(defaults.first['status'], 'active');
  });

  test('migration V6 -> V7 does not affect cards table', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    await MemoMindDatabase.createV6(db);

    // Seed document, page, block prerequisites
    await db.insert('documents', {
      'document_id': 'doc-v7',
      'title': 'Tài liệu V7',
      'status': 'ready_for_generation',
      'privacy': 'private',
      'page_count': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('source_pages', {
      'page_id': 'page-v7',
      'document_id': 'doc-v7',
      'page_number': 1,
      'original_page_number': 1,
      'source': 'camera',
      'data_relative_path': 'data/v7.jpg',
      'mime_type': 'image/jpeg',
      'file_size_bytes': 100,
      'width': 800,
      'height': 600,
      'sha256': 'v7hash',
      'quality_code': 'ok',
      'quality_warning_accepted': 0,
      'created_at': 1,
      'normalization_status': 'source_ready',
    });
    await db.insert('source_blocks', {
      'block_id': 'blk-v7',
      'document_id': 'doc-v7',
      'page_id': 'page-v7',
      'page_number': 1,
      'order_index': 0,
      'raw_text': 'Nguồn',
      'normalized_text': 'Nguồn chuẩn',
      'confidence_source': 'mlkit',
      'status': 'verified',
      'created_at': 1,
      'updated_at': 1,
    });

    // Insert deck and card at V6
    await db.insert('decks', {
      'deck_id': 'dk-v7',
      'title': 'Deck test',
      'tone': 'indigo',
      'card_count': 1,
      'created_at': 2,
      'updated_at': 2,
    });
    await db.insert('cards', {
      'card_id': 'card-v7',
      'deck_id': 'dk-v7',
      'type': 'BASIC',
      'front': 'Câu hỏi?',
      'back': 'Trả lời',
      'source_document_id': 'doc-v7',
      'source_page_id': 'page-v7',
      'source_page_number': 1,
      'source_block_id': 'blk-v7',
      'source_quote': 'Nguồn chuẩn',
      'status': 'active',
      'repetitions': 0,
      'interval_days': 0,
      'ease_factor': 2.5,
      'due_date': 3,
      'created_at': 2,
      'updated_at': 2,
    });

    // Migrate to V7
    await MemoMindDatabase.migrateV6ToV7(db);

    // Card should be completely unchanged
    final cards = await db.query(
      'cards',
      where: 'card_id = ?',
      whereArgs: ['card-v7'],
    );
    expect(cards.length, 1);
    expect(cards.first['type'], 'BASIC');
    expect(cards.first['front'], 'Câu hỏi?');
    expect(cards.first['back'], 'Trả lời');
    expect(cards.first['status'], 'active');
    expect(cards.first['source_block_id'], 'blk-v7');
    expect(cards.first['source_quote'], 'Nguồn chuẩn');

    // Deck should have new columns with defaults
    final decks = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: ['dk-v7'],
    );
    expect(decks.first['tags'], '[]');
    expect(decks.first['status'], 'active');
    expect(decks.first['card_count'], 1);
  });
}
