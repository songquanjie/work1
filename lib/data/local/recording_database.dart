import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/recording.dart';

/// 本地录音元数据。页面不要直接操作 SQLite。
abstract class RecordingStore {
  Future<void> insert(Recording recording);
  Future<void> update(Recording recording);
  Future<void> delete(String id);
  Future<Recording?> findById(String id);
  Future<List<Recording>> findAllNewestFirst();
  Future<void> close();
}

/// schema v3 才有 status / transcript。升级路径：v1 重建，v2 加列。
class RecordingDatabase implements RecordingStore {
  RecordingDatabase({Database? database}) : _injected = database;

  final Database? _injected;
  Database? _db;

  static const int schemaVersion = 3;

  static Future<void> createSchema(Database db, int _) async {
    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        processing_stage TEXT,
        remote_task_id TEXT,
        transcript TEXT,
        summary TEXT,
        error_code TEXT,
        error_message TEXT,
        failed_stage TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_checked_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_recordings_created_at ON recordings(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_recordings_status ON recordings(status)',
    );
  }

  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= newVersion) {
      return;
    }
    // v1 表结构与 v3 差太多，重建比逐列 ADD 更不容易漏字段。
    if (oldVersion < 2) {
      await db.execute('DROP INDEX IF EXISTS idx_recordings_created_at');
      await db.execute('ALTER TABLE recordings RENAME TO recordings_old');
      await createSchema(db, newVersion);
      await db.execute('''
        INSERT INTO recordings (
          id, name, file_name, local_path, duration_ms, created_at, updated_at, status
        )
        SELECT id, name, file_name, local_path, duration_ms, created_at, created_at, 'pendingUpload'
        FROM recordings_old
      ''');
      await db.execute('DROP TABLE recordings_old');
      return;
    }
    // 当前真机包从 schema v2 升上来：旧表只有基础列，逐列 ADD。
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE recordings ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE recordings ADD COLUMN status TEXT NOT NULL DEFAULT 'pendingUpload'",
      );
      await db.execute('ALTER TABLE recordings ADD COLUMN processing_stage TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN remote_task_id TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN transcript TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN summary TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN error_code TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN error_message TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN failed_stage TEXT');
      await db.execute(
        'ALTER TABLE recordings ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE recordings ADD COLUMN last_checked_at INTEGER');
      await db.execute(
        'UPDATE recordings SET updated_at = created_at WHERE updated_at = 0',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status)',
      );
    }
  }

  Future<void> init() async {
    if (_injected != null) {
      _db = _injected;
      return;
    }
    final String dbPath = p.join(await getDatabasesPath(), 'echonote.db');
    _db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: createSchema,
      onUpgrade: upgradeSchema,
    );
  }

  Database get _database {
    final Database? db = _db;
    if (db == null) {
      throw StateError('RecordingDatabase has not been initialized');
    }
    return db;
  }

  @override
  Future<void> insert(Recording recording) async {
    await _database.insert('recordings', recording.toMap());
  }

  @override
  Future<void> update(Recording recording) async {
    await _database.update(
      'recordings',
      recording.toMap(),
      where: 'id = ?',
      whereArgs: <Object>[recording.id],
    );
  }

  @override
  Future<void> delete(String id) async {
    await _database.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<Recording?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'recordings',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Recording.fromMap(rows.first);
  }

  @override
  Future<List<Recording>> findAllNewestFirst() async {
    final List<Map<String, Object?>> rows = await _database.query(
      'recordings',
      orderBy: 'created_at DESC',
    );
    return rows
        .map((Map<String, Object?> row) => Recording.fromMap(row))
        .toList();
  }

  @override
  Future<void> close() async {
    if (_injected != null) {
      return;
    }
    final Database? db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
