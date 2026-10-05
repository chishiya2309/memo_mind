import 'package:sqflite/sqflite.dart';

const syncPrimaryKeys = <String, String>{
  'documents': 'document_id',
  'source_pages': 'page_id',
  'page_normalizations': 'page_id',
  'ocr_page_results': 'page_id',
  'source_blocks': 'block_id',
  'decks': 'deck_id',
  'cards': 'card_id',
  'review_sessions': 'session_id',
  'review_events': 'event_id',
  'card_schedules': 'card_id',
};

/// Triggers capture mutations in the transaction that changes study data.
/// Incoming changes turn capture off; it is never disabled outside a transaction.
Future<void> createSyncSchema(DatabaseExecutor db) async {
  await db.execute(
    "ALTER TABLE review_sessions ADD COLUMN device_id TEXT NOT NULL DEFAULT ''",
  );
  await db.execute(
    'ALTER TABLE review_sessions ADD COLUMN is_local INTEGER NOT NULL DEFAULT 1',
  );
  await db.execute('DROP INDEX idx_review_active_session');
  await db.execute(
    "CREATE UNIQUE INDEX idx_review_active_session ON review_sessions(is_local) WHERE status='active' AND is_local=1",
  );
  await db.execute('ALTER TABLE review_events ADD COLUMN schedule_after TEXT');
  await db.execute(
    "ALTER TABLE review_events ADD COLUMN scheduler_version TEXT NOT NULL DEFAULT 'sm2-v1'",
  );
  await db.execute('''CREATE TABLE card_schedules(
    card_id TEXT PRIMARY KEY, repetitions INTEGER NOT NULL,
    interval_days INTEGER NOT NULL, ease_factor REAL NOT NULL,
    due_date INTEGER NOT NULL, reviewed_at INTEGER NOT NULL,
    device_id TEXT NOT NULL, event_id TEXT NOT NULL,
    scheduler_version TEXT NOT NULL DEFAULT 'sm2-v1')''');
  // Preserve the existing scheduler state, rather than replaying old reviews.
  await db.execute('''INSERT INTO card_schedules
    SELECT card_id,repetitions,interval_days,ease_factor,due_date,
      COALESCE((SELECT reviewed_at FROM review_events e WHERE e.card_id=c.card_id ORDER BY reviewed_at DESC,device_id DESC,event_id DESC LIMIT 1),0),
      COALESCE((SELECT device_id FROM review_events e WHERE e.card_id=c.card_id ORDER BY reviewed_at DESC,device_id DESC,event_id DESC LIMIT 1),''),
      COALESCE((SELECT event_id FROM review_events e WHERE e.card_id=c.card_id ORDER BY reviewed_at DESC,device_id DESC,event_id DESC LIMIT 1),''),'sm2-v1'
    FROM cards c''');
  await db.execute(
    'CREATE TABLE sync_control(id INTEGER PRIMARY KEY CHECK(id=1), applying INTEGER NOT NULL DEFAULT 0, group_id TEXT)',
  );
  await db.insert('sync_control', {'id': 1});
  await db.execute(
    'CREATE TABLE sync_meta(table_name TEXT NOT NULL,entity_id TEXT NOT NULL,version INTEGER NOT NULL,data TEXT NOT NULL,deleted INTEGER NOT NULL,PRIMARY KEY(table_name,entity_id))',
  );
  await db.execute('''CREATE TABLE sync_outbox(
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL,
    entity_id TEXT NOT NULL, group_id TEXT NOT NULL, operation_id TEXT NOT NULL,
    base_version INTEGER NOT NULL, before_data TEXT, data TEXT NOT NULL,
    deleted INTEGER NOT NULL)''');
  await db.execute(
    'CREATE INDEX idx_sync_outbox_entity ON sync_outbox(table_name,entity_id,sequence)',
  );
  await db.execute(
    'CREATE TABLE sync_packets(group_id TEXT PRIMARY KEY,payload TEXT NOT NULL,sequences TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE sync_state(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE sync_conflicts(conflict_id TEXT PRIMARY KEY,payload TEXT NOT NULL)',
  );
  await db.execute('CREATE TABLE sync_imports(source_id TEXT PRIMARY KEY)');
  await db.execute(
    'CREATE TABLE sync_inbox(version INTEGER PRIMARY KEY,payload TEXT NOT NULL)',
  );
  for (final entry in syncPrimaryKeys.entries) {
    final columns = (await db.rawQuery('PRAGMA table_info(${entry.key})'))
        .map((r) => r['name'] as String)
        .toList();
    String json(String prefix) =>
        'json_object(${columns.map((c) => "'$c',$prefix.$c").join(',')})';
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = operation == 'DELETE' ? 'OLD' : 'NEW';
      final before = operation == 'INSERT' ? 'NULL' : json('OLD');
      final deleted = operation == 'DELETE'
          ? '1'
          : (columns.contains('status') &&
                    ['cards', 'decks', 'source_blocks'].contains(entry.key)
                ? "CASE WHEN NEW.status='deleted' THEN 1 ELSE 0 END"
                : '0');
      await db.execute(
        '''CREATE TRIGGER sync_${entry.key}_${operation.toLowerCase()}
        AFTER $operation ON ${entry.key}
        WHEN (SELECT applying FROM sync_control WHERE id=1)=0
          ${operation == 'UPDATE' ? 'AND ${json('OLD')} != ${json('NEW')}' : ''}
        BEGIN INSERT INTO sync_outbox(table_name,entity_id,group_id,operation_id,base_version,before_data,data,deleted)
          VALUES('${entry.key}',$row.${entry.value},
            COALESCE((SELECT group_id FROM sync_control WHERE id=1),lower(hex(randomblob(16)))),
            lower(hex(randomblob(16))),
            COALESCE((SELECT version FROM sync_meta WHERE table_name='${entry.key}' AND entity_id=$row.${entry.value}),0),
            $before,${json(row)},$deleted); END''',
      );
    }
  }
  await db.execute(
    '''CREATE TRIGGER sync_new_card_schedule AFTER INSERT ON cards
    WHEN (SELECT applying FROM sync_control WHERE id=1)=0 BEGIN
      INSERT OR IGNORE INTO card_schedules VALUES(NEW.card_id,NEW.repetitions,
        NEW.interval_days,NEW.ease_factor,NEW.due_date,0,'','','sm2-v1'); END''',
  );
  for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
    await db.execute(
      'CREATE TRIGGER revision_card_schedules_${operation.toLowerCase()} AFTER $operation ON card_schedules BEGIN UPDATE workspace_revision SET revision=revision+1 WHERE id=1; END',
    );
  }
}
