import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static Future<Database>? _opening;

  Future<Database> get database async {
    final opened = _database;
    if (opened != null) return opened;
    // Plusieurs providers reclament la base en parallele au demarrage : on ne
    // doit ouvrir (et migrer) le fichier qu'une seule fois.
    return _opening ??= _initDatabase()
        .then((db) => _database = db)
        .whenComplete(() => _opening = null);
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ikavisite.db');

    final db = await openDatabase(
      path,
      version: 13,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    try { await db.execute('PRAGMA journal_mode=WAL'); } catch (_) {}
    try { await db.execute('PRAGMA foreign_keys=ON'); } catch (_) {}
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
    if (oldVersion < 11) {
      // `visits_cache` stockait une liste entiere dans une seule ligne JSON.
      // Android refusant de relire une ligne de plus de 2 Mo, la liste
      // devenait invisible des quelques visites hors ligne. On la remplace par
      // une vraie table locale, une ligne par visite. Le contenu de l'ancien
      // cache n'est pas migre : les visites du serveur seront retelechargees,
      // et les saisies hors ligne sont reconstruites depuis `pending_sync`,
      // qui les contient integralement.
      await db.execute('DROP TABLE IF EXISTS visits_cache');
      await _createVisitsTables(db);
    }
    if (oldVersion < 12) {
      // Un envoi definitivement refuse par le serveur etait reessaye a chaque
      // synchronisation, indefiniment. On compte les tentatives pour pouvoir
      // le mettre de cote (statut 2) et le montrer a l'agent.
      await db.execute(
          'ALTER TABLE pending_sync ADD COLUMN tentatives INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 13) {
      // Une visite figurait autant de fois qu'elle apparaissait de listes.
      // Elle est desormais unique, et rattachee a ses listes par une table de
      // liaison. `visit_detail_cache` disparait : la table `visits` fait
      // maintenant office de fiche complete.
      await db.execute('DROP TABLE IF EXISTS visit_detail_cache');
      await db.execute('DROP TABLE IF EXISTS visits');
      await db.execute('DROP TABLE IF EXISTS visit_listes');
      await db.execute('DROP TABLE IF EXISTS visits_meta');
      await _createVisitsTables(db);
    }
  }

  /// Base locale des visites : une ligne par visite, quelques kilo-octets
  /// chacune. `liste` distingue les quatre vues (du jour, en cours, terminees,
  /// excedees) ; `ordre` conserve le classement, les valeurs negatives placant
  /// les saisies hors ligne en tete.
  Future<void> _createVisitsTables(Database db) async {
    // Repertoire local des visiteurs. Alimente aussi bien par le serveur que
    // par les saisies hors ligne : c'est lui qui permet de retrouver la
    // nationalite et le telephone d'un visiteur connu sans reseau.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visiteurs (
        uuid            TEXT PRIMARY KEY,
        id              INTEGER,
        nom             TEXT,
        prenom          TEXT,
        genre           TEXT,
        telephone       TEXT,
        email           TEXT,
        numero_piece    TEXT,
        numero_nip      TEXT,
        nationalite     TEXT,
        profession      TEXT,
        adresse         TEXT,
        piece_identite  TEXT,
        date_naissance  TEXT,
        lieu_naissance  TEXT,
        pays_delivrance TEXT,
        date_delivrance TEXT,
        updated_at      TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_visiteurs_piece ON visiteurs (numero_piece)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_visiteurs_nip ON visiteurs (numero_nip)');

    // Une visite, une ligne — quelle que soit le nombre de listes ou elle
    // apparait. C'est aussi la fiche complete, consultee par l'ecran de detail.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id            INTEGER PRIMARY KEY,
        uuid          TEXT NOT NULL UNIQUE,
        visiteur_uuid TEXT REFERENCES visiteurs (uuid) ON DELETE SET NULL,
        est_local     INTEGER NOT NULL DEFAULT 0,
        statut        TEXT,
        date_visite   TEXT,
        heure_arrivee TEXT,
        personnel_id  INTEGER,
        updated_at    TEXT NOT NULL,
        data_json     TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_visits_local ON visits (est_local)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_visits_date ON visits (date_visite)');

    // Rattachement d'une visite aux vues qui l'affichent. `visit_id` renvoie a
    // `visits.id` sans contrainte declaree : une reecriture de visite passe par
    // INSERT OR REPLACE, et une cascade effacerait alors les rattachements.
    // L'integrite est tenue par le code, qui supprime toujours les liens avant
    // la visite. `ordre` conserve le classement ; les valeurs negatives placent
    // les saisies hors ligne en tete.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visit_listes (
        liste    TEXT NOT NULL,
        visit_id INTEGER NOT NULL,
        ordre    INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (liste, visit_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_visit_listes_ordre ON visit_listes (liste, ordre)');

    // Nombre total annonce par le serveur pour chaque liste, servant a la
    // pagination. Les visites locales s'y ajoutent au moment de l'affichage.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits_meta (
        liste        TEXT PRIMARY KEY,
        server_count INTEGER NOT NULL DEFAULT 0,
        updated_at   TEXT NOT NULL
      )
    ''');
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
        status INTEGER DEFAULT 0,
        tentatives INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createVisitsTables(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dropdown_cache (
        cache_key TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_sync_status ON pending_sync (status)');
    try { await db.execute('PRAGMA journal_mode=WAL'); } catch (_) {}
    try { await db.execute('PRAGMA foreign_keys=ON'); } catch (_) {}
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
