import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ikavisite.db');

    final db = await openDatabase(
      path,
      version: 10,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS users');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER,
          uuid TEXT,
          username TEXT NOT NULL,
          email TEXT,
          password TEXT,
          access_token TEXT,
          refresh_token TEXT,
          first_name TEXT,
          last_name TEXT,
          telephone_mobile TEXT,
          statut TEXT,
          role TEXT,
          porte_entree TEXT,
          porte_entree_id INTEGER,
          is_superuser INTEGER DEFAULT 0,
          is_staff INTEGER DEFAULT 0,
          is_active INTEGER DEFAULT 1,
          is_connected INTEGER DEFAULT 0,
          last_login TEXT,
          date_joined TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_sync (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          status INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE users ADD COLUMN role TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN porte_entree TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN porte_entree_id INTEGER');
      await db.execute('ALTER TABLE users ADD COLUMN date_joined TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS visits_cache (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cache_type TEXT NOT NULL,
          page INTEGER NOT NULL DEFAULT 1,
          data_json TEXT NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS visit_detail_cache (
          id INTEGER PRIMARY KEY,
          data_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute('DROP TABLE IF EXISTS visits');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dropdown_cache (
          cache_key TEXT PRIMARY KEY,
          data_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_visits_cache_type_page ON visits_cache (cache_type, page)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_sync_status ON pending_sync (status)');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER,
        uuid TEXT,
        username TEXT NOT NULL,
        email TEXT,
        password TEXT,
        access_token TEXT,
        refresh_token TEXT,
        first_name TEXT,
        last_name TEXT,
        telephone_mobile TEXT,
        statut TEXT,
        role TEXT,
        porte_entree TEXT,
        porte_entree_id INTEGER,
        is_superuser INTEGER DEFAULT 0,
        is_staff INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        is_connected INTEGER DEFAULT 0,
        last_login TEXT,
        date_joined TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dashboard_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stats_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cache_type TEXT NOT NULL,
        page INTEGER NOT NULL DEFAULT 1,
        data_json TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS visit_detail_cache (
        id INTEGER PRIMARY KEY,
        data_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dropdown_cache (
        cache_key TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_visits_cache_type_page ON visits_cache (cache_type, page)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_sync_status ON pending_sync (status)');
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA foreign_keys=ON');
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  Future<int> update(String table, Map<String, dynamic> values,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return await db.update(table, values,
        where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> query(String table,
      {String? where,
      List<dynamic>? whereArgs,
      String? orderBy,
      int? limit}) async {
    final db = await database;
    return await db.query(table,
        where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
  }

  Future<Map<String, dynamic>?> getFirst(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final results = await query(table, where: where, whereArgs: whereArgs, limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> clearTable(String table) async {
    final db = await database;
    await db.delete(table);
  }
}
