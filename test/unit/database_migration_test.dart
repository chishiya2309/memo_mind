import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'version 1 image data migrates and version 2 accepts PDF metadata',
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

      final migrated = (await db.query('source_pages')).single;
      expect(migrated['original_page_number'], 1);
      expect(
        migrated['data_relative_path'],
        'documents/image-document/pages/page.jpg',
      );
      expect(migrated['source'], 'gallery');

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
      });

      final pdfPage = (await db.query(
        'source_pages',
        where: 'document_id = ?',
        whereArgs: ['pdf-document'],
      )).single;
      expect(pdfPage['source'], 'pdf');
      expect(pdfPage['original_page_number'], 7);
    },
  );
}
