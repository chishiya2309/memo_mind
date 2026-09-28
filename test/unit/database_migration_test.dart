import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'version 1 data migrates through v3 with normalization defaults',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('''
      CREATE TABLE documents (
        document_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status = 'pending_processing'),
        privacy TEXT NOT NULL DEFAULT 'private' CHECK(privacy = 'private'),
        page_count INTEGER NOT NULL DEFAULT 0 CHECK(page_count >= 0),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await db.execute('''
      CREATE TABLE source_pages (
        page_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_number INTEGER NOT NULL CHECK(page_number > 0),
        source TEXT NOT NULL CHECK(source IN ('camera', 'gallery')),
        original_relative_path TEXT NOT NULL UNIQUE,
        mime_type TEXT NOT NULL CHECK(mime_type IN ('image/jpeg', 'image/png')),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
        width INTEGER NOT NULL CHECK(width > 0),
        height INTEGER NOT NULL CHECK(height > 0),
        sha256 TEXT NOT NULL,
        quality_code TEXT NOT NULL,
        quality_warning_accepted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE,
        UNIQUE(document_id, page_number)
      )
    ''');
      await db.execute(
        'CREATE INDEX idx_source_pages_document_id '
        'ON source_pages(document_id)',
      );
      await db.insert('documents', {
        'document_id': 'image-document',
        'title': 'Ảnh cũ',
        'status': 'pending_processing',
        'privacy': 'private',
        'page_count': 1,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert('source_pages', {
        'page_id': 'image-page',
        'document_id': 'image-document',
        'page_number': 1,
        'source': 'gallery',
        'original_relative_path': 'documents/image-document/pages/page.jpg',
        'mime_type': 'image/jpeg',
        'file_size_bytes': 100,
        'width': 10,
        'height': 20,
        'sha256': 'image-hash',
        'quality_code': 'ok',
        'quality_warning_accepted': 0,
        'created_at': 1,
      });

      await MemoMindDatabase.migrateV1ToV2(db);
      await MemoMindDatabase.migrateV2ToV3(db);

      final migrated = (await db.query('source_pages')).single;
      expect(migrated['original_page_number'], 1);
      expect(
        migrated['data_relative_path'],
        'documents/image-document/pages/page.jpg',
      );
      expect(migrated['source'], 'gallery');
      expect(migrated['normalization_status'], 'pending');

      await db.insert('documents', {
        'document_id': 'pdf-document',
        'title': 'Bài giảng',
        'status': 'pending_ocr',
        'privacy': 'private',
        'page_count': 1,
        'original_file_name': 'Bài giảng.pdf',
        'original_file_relative_path':
            'documents/pdf-document/originals/original.pdf',
        'original_file_mime_type': 'application/pdf',
        'original_file_size_bytes': 200,
        'original_file_sha256': 'pdf-hash',
        'created_at': 2,
        'updated_at': 2,
      });
      await db.insert('source_pages', {
        'page_id': 'pdf-page',
        'document_id': 'pdf-document',
        'page_number': 1,
        'original_page_number': 7,
        'source': 'pdf',
        'data_relative_path': 'documents/pdf-document/pages/page.png',
        'mime_type': 'image/png',
        'file_size_bytes': 120,
        'width': 100,
        'height': 140,
        'sha256': 'page-hash',
        'quality_code': 'not_inspected',
        'quality_warning_accepted': 0,
        'created_at': 2,
        'normalization_status': 'source_ready',
      });

      final pdfPage = (await db.query(
        'source_pages',
        where: 'document_id = ?',
        whereArgs: ['pdf-document'],
      )).single;
      expect(pdfPage['source'], 'pdf');
      expect(pdfPage['original_page_number'], 7);
      expect(pdfPage['normalization_status'], 'source_ready');
      expect(await db.query('page_normalizations'), isEmpty);

      // Migrate to V4 (OCR and SourceBlocks)
      await MemoMindDatabase.migrateV3ToV4(db);

      // Update document to pending_ocr_review and ready_for_generation
      await db.update(
        'documents',
        {'status': 'pending_ocr_review'},
        where: 'document_id = ?',
        whereArgs: ['image-document'],
      );

      final updatedDoc = (await db.query(
        'documents',
        where: 'document_id = ?',
        whereArgs: ['image-document'],
      )).single;
      expect(updatedDoc['status'], 'pending_ocr_review');

      // Insert OCR page result
      await db.insert('ocr_page_results', {
        'page_id': 'image-page',
        'document_id': 'image-document',
        'status': 'completed',
        'recognized_language': 'vi',
        'raw_full_text': 'Nội dung tiếng Việt',
        'updated_at': 3,
      });

      // Insert source block
      await db.insert('source_blocks', {
        'block_id': 'block-1',
        'document_id': 'image-document',
        'page_id': 'image-page',
        'page_number': 1,
        'order_index': 0,
        'raw_text': 'Nội dung tiếng Việt',
        'normalized_text': 'Nội dung tiếng Việt đã sửa',
        'box_left': 0.1,
        'box_top': 0.2,
        'box_width': 0.5,
        'box_height': 0.3,
        'has_valid_box': 1,
        'confidence': 0.92,
        'confidence_source': 'mlkit',
        'status': 'draft',
        'created_at': 3,
        'updated_at': 3,
      });

      final blocks = await db.query(
        'source_blocks',
        where: 'page_id = ?',
        whereArgs: ['image-page'],
      );
      expect(blocks.length, 1);
      expect(blocks.first['raw_text'], 'Nội dung tiếng Việt');
      expect(blocks.first['normalized_text'], 'Nội dung tiếng Việt đã sửa');
      expect(blocks.first['confidence'], 0.92);

      // Test cascade delete
      await db.delete(
        'documents',
        where: 'document_id = ?',
        whereArgs: ['image-document'],
      );
      expect(
        await db.query(
          'source_blocks',
          where: 'document_id = ?',
          whereArgs: ['image-document'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'ocr_page_results',
          where: 'document_id = ?',
          whereArgs: ['image-document'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'version 4 data migrates to v5 with decks and cards tables',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys = ON');

      // Create V4 schema
      await MemoMindDatabase.createV4(db);

      // Insert prerequisites
      await db.insert('documents', {
        'document_id': 'doc-v5',
        'title': 'Tài liệu ôn thi',
        'status': 'ready_for_generation',
        'privacy': 'private',
        'page_count': 1,
        'created_at': 10,
        'updated_at': 10,
      });

      await db.insert('source_pages', {
        'page_id': 'page-v5',
        'document_id': 'doc-v5',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'camera',
        'data_relative_path': 'data/page1.jpg',
        'mime_type': 'image/jpeg',
        'file_size_bytes': 1000,
        'width': 800,
        'height': 600,
        'sha256': 'dummy',
        'quality_code': 'good',
        'quality_warning_accepted': 0,
        'created_at': 10,
        'normalization_status': 'source_ready',
      });

      await db.insert('source_blocks', {
        'block_id': 'blk-v5',
        'document_id': 'doc-v5',
        'page_id': 'page-v5',
        'page_number': 1,
        'order_index': 0,
        'raw_text': 'Nội dung khối nguồn',
        'normalized_text': 'Nội dung khối nguồn đã chuẩn hóa',
        'box_left': 0.1,
        'box_top': 0.1,
        'box_width': 0.8,
        'box_height': 0.2,
        'has_valid_box': 1,
        'confidence': 0.95,
        'confidence_source': 'mlkit',
        'status': 'verified',
        'created_at': 10,
        'updated_at': 10,
      });

      // Migrate to V5
      await MemoMindDatabase.migrateV4ToV5(db);

      // Insert deck
      await db.insert('decks', {
        'deck_id': 'deck-v5',
        'title': 'Bộ thẻ Lịch sử',
        'description': 'Mô tả bộ thẻ',
        'tone': 'indigo',
        'card_count': 1,
        'created_at': 20,
        'updated_at': 20,
      });

      // Insert card with source attribution
      await db.insert('cards', {
        'card_id': 'card-v5',
        'deck_id': 'deck-v5',
        'type': 'flashcard',
        'format': 'qa',
        'question': 'Nội dung câu hỏi?',
        'answer': 'Câu trả lời chuẩn',
        'source_document_id': 'doc-v5',
        'source_page_id': 'page-v5',
        'source_page_number': 1,
        'source_block_id': 'blk-v5',
        'source_quote': 'khối nguồn đã chuẩn hóa',
        'confidence': 0.9,
        'status': 'active',
        'repetitions': 0,
        'interval_days': 0,
        'ease_factor': 2.5,
        'due_date': 30,
        'created_at': 20,
        'updated_at': 20,
      });

      final cards = await db.query(
        'cards',
        where: 'deck_id = ?',
        whereArgs: ['deck-v5'],
      );
      expect(cards.length, 1);
      expect(cards.first['source_block_id'], 'blk-v5');
      expect(cards.first['source_quote'], 'khối nguồn đã chuẩn hóa');

      // Test Cascade delete when Deck is deleted
      await db.delete(
        'decks',
        where: 'deck_id = ?',
        whereArgs: ['deck-v5'],
      );
      expect(
        await db.query(
          'cards',
          where: 'deck_id = ?',
          whereArgs: ['deck-v5'],
        ),
        isEmpty,
      );
    },
  );
}
