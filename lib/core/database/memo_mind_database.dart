import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MemoMindDatabase {
  MemoMindDatabase._();

  static final MemoMindDatabase instance = MemoMindDatabase._();

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'memo_mind.db'),
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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
      },
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
