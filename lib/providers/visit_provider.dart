import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/visit.dart';
import '../services/visit_media.dart';
import '../services/visit_service.dart';
import '../services/cancel_token.dart';
import 'connectivity_provider.dart';

typedef _VisiteFetcher = Future<VisitListResponse> Function(int page);

class _VisiteListState {
  List<Visit> items = [];
  int page = 1;
  int count = 0;

  /// Nombre de lignes déjà lues en base pour cette liste (avant filtrage
  /// « aujourd'hui »). Permet à `_nextPage` de ne lire que la tranche
  /// suivante au lieu de relire toute la liste depuis le début à chaque
  /// défilement — sans cela, le coût de lecture/décodage JSON croît de façon
  /// quadratique et le défilement devient perceptiblement plus lent au fil
  /// des pages.
  int rawFetched = 0;

  int get totalPages => (count / _VisiteListState.pageSize).ceil().clamp(1, 9999);
  static const int pageSize = 10;
}

class VisitProvider extends ChangeNotifier {
  final VisitService _visitService = VisitService();
  final DatabaseHelper _db = DatabaseHelper();
  final ConnectivityProvider _connectivity;
  CancelToken? _cancelToken;

  final Map<String, _VisiteListState> _states = {
    'today': _VisiteListState(),
    'en_cours': _VisiteListState(),
    'terminees': _VisiteListState(),
    'excedees': _VisiteListState(),
  };

  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;

  static const String _todayKey = 'today';
  static const String _enCoursKey = 'en_cours';
  static const String _termineesKey = 'terminees';
  static const String _excedeesKey = 'excedees';

  /// Listes qui, cote mobile, ne doivent montrer que la journee en cours.
  /// « En cours » et « excedees » en sont volontairement exclues : une visite
  /// ouverte hier et toujours en cours doit rester visible.
  static const Set<String> _todayScopedKeys = {_todayKey, _termineesKey};

  VisitProvider(this._connectivity);

  /// Garde-fou cote client sur le perimetre « jour meme ». L'API recoit deja
  /// `aujourdhui=true`, mais le cache SQLite peut dater de la veille : sans ce
  /// filtre, ouvrir l'application le lendemain affiche les visites d'hier.
  List<Visit> _scopeToToday(String key, List<Visit> items) {
    if (!_todayScopedKeys.contains(key)) return items;
    return items.where((v) {
      final d = v.dateVisite;
      // Une visite sans date est conservee : on ne masque pas une donnee
      // uniquement parce qu'un champ manque.
      return d == null || _isToday(d);
    }).toList();
  }

  void cancelPending() {
    _cancelToken?.cancel();
  }

  List<Visit> get visitsToday => _states[_todayKey]!.items;
  List<Visit> get visitsEnCours => _states[_enCoursKey]!.items;
  List<Visit> get visitsTerminees => _states[_termineesKey]!.items;
  List<Visit> get visitsExcedees => _states[_excedeesKey]!.items;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;

  int get pageToday => _states[_todayKey]!.page;
  int get countToday => _states[_todayKey]!.count;
  int get totalPagesToday => _states[_todayKey]!.totalPages;

  int get pageEnCours => _states[_enCoursKey]!.page;
  int get countEnCours => _states[_enCoursKey]!.count;
  int get totalPagesEnCours => _states[_enCoursKey]!.totalPages;

  int get pageTerminees => _states[_termineesKey]!.page;
  int get countTerminees => _states[_termineesKey]!.count;
  int get totalPagesTerminees => _states[_termineesKey]!.totalPages;

  int get pageExcedees => _states[_excedeesKey]!.page;
  int get countExcedees => _states[_excedeesKey]!.count;
  int get totalPagesExcedees => _states[_excedeesKey]!.totalPages;

  // ── Dropdowns ──

  Future<void> prefetchAndCacheDropdowns(String token, {bool force = false}) async {
    if (!_connectivity.isConnected) return;
    try {
      if (!force) {
        final existing = await _db.query('dropdown_cache',
            where: 'cache_key = ?', whereArgs: ['types_visite'], limit: 1);
        if (existing.isNotEmpty) {
          final updatedAtStr = existing.first['updated_at'] as String?;
          if (updatedAtStr != null) {
            final updatedAt = DateTime.tryParse(updatedAtStr);
            if (updatedAt != null &&
                DateTime.now().difference(updatedAt).inHours < 4) {
              debugPrint('[VisitProvider] Le cache des dropdowns est récent (< 4h), récupération réseau ignorée.');
              return;
            }
          }
        }
      }

      final results = await Future.wait([
        _visitService.getTypesVisite(token),
        _visitService.getPortesEntree(token),
        _visitService.getPersonnel(token),
        _visitService.getDepartements(token),
        _visitService.getReferences(token),
      ]);
      final refs = results[4] as Map<String, dynamic>;
      final now = DateTime.now().toIso8601String();
      for (final entry in [
        ['types_visite', jsonEncode(results[0])],
        ['portes_entree', jsonEncode(results[1])],
        ['personnel', jsonEncode(results[2])],
        ['departements', jsonEncode(results[3])],
        ['references', jsonEncode({
          'nationalites': (refs['nationalites'] as List?)?.cast<String>() ?? [],
          'pays': (refs['pays'] as List?)?.cast<String>() ?? [],
          'types_piece': (refs['types_piece'] as List?)?.cast<String>() ?? [],
        })],
      ]) {
        final key = entry[0];
        final data = entry[1];
        final existing = await _db.query('dropdown_cache',
            where: 'cache_key = ?', whereArgs: [key]);
        if (existing.isNotEmpty) {
          await _db.update('dropdown_cache', {'data_json': data, 'updated_at': now},
              where: 'cache_key = ?', whereArgs: [key]);
        } else {
          await _db.insert('dropdown_cache', {'cache_key': key, 'data_json': data, 'updated_at': now});
        }
      }
    } catch (_) {}
  }

  // ── Generic list methods ──

  Future<void> _loadList(String key, _VisiteFetcher fetcher, String token,
      {Future<bool> Function()? onUnauthorized}) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final state = _states[key]!;
    state.page = 1;
    _error = null;

    await _rebuildLocalVisitsFromQueue();

    // 1. Afficher immédiatement ce que contient la base locale
    final firstRaw = await _readVisits(key, offset: 0, limit: _VisiteListState.pageSize);
    state.items = _scopeToToday(key, firstRaw);
    state.rawFetched = firstRaw.length;
    state.count = await _totalCount(key);
    notifyListeners();

    if (!_connectivity.isConnected) {
      if (state.items.isEmpty) {
        _error = 'Aucune connexion Internet et aucune donnée en cache';
      }
      notifyListeners(); // Notifie l'interface en mode hors ligne
      return;
    }

    _isRefreshing = true;
    notifyListeners();

    try {
      _cancelToken!.throwIfCancelled();
      final result = await fetcher(1);
      await _storeServerPage(key, result.items, 1, result.count);
      // On relit la base : elle est désormais la seule source d'affichage, et
      // elle contient aussi les saisies hors ligne, placées en tête.
      final raw = await _readVisits(key, offset: 0, limit: _VisiteListState.pageSize);
      state.items = _scopeToToday(key, raw);
      state.rawFetched = raw.length;
      state.count = await _totalCount(key);
      _error = null;

      // Préchargement en arrière-plan des pages suivantes si connecté
      if (result.count > _VisiteListState.pageSize) {
        final totalP = (result.count / _VisiteListState.pageSize).ceil();
        final maxPrefetch = totalP.clamp(1, 5); // Limiter à la page 5 max
        for (int p = 2; p <= maxPrefetch; p++) {
          _prefetchPageInBackground(fetcher, key, p);
        }
      }
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) {
          _isRefreshing = false;
          await _loadList(key, fetcher, token);
          return;
        }
      }
      if (state.items.isEmpty) _error = msg;
    }

    _isRefreshing = false;
    notifyListeners();
  }

  void _prefetchPageInBackground(_VisiteFetcher fetcher, String liste, int page) async {
    try {
      if (!_connectivity.isConnected) return;
      final result = await fetcher(page);
      await _storeServerPage(liste, result.items, page, result.count);
      debugPrint('[VisitProvider] Préchargement en arrière-plan réussi pour $liste page $page');
    } catch (e) {
      debugPrint('[VisitProvider] Échec du préchargement en arrière-plan pour $liste page $page : $e');
    }
  }

  Future<String?> _nextPage(String key, _VisiteFetcher fetcher, String token) async {
    if (_isLoading) return null;
    final state = _states[key]!;
    if (state.page >= state.totalPages) return null;

    _isLoading = true;
    notifyListeners();

    String? errorResult;
    final nextPage = state.page + 1;

    if (_connectivity.isConnected) {
      try {
        final result = await fetcher(nextPage);
        await _storeServerPage(key, result.items, nextPage, result.count);
      } catch (e) {
        _error = e.toString();
        errorResult = _error;
      }
    }

    // Seule la tranche suivante est lue — jamais depuis le début — pour que
    // le défilement reste rapide même après plusieurs milliers de visites
    // déjà affichées.
    final raw = await _readVisits(key,
        offset: state.rawFetched, limit: _VisiteListState.pageSize);
    if (raw.isNotEmpty) {
      state.items = [...state.items, ..._scopeToToday(key, raw)];
      state.rawFetched += raw.length;
      state.page = nextPage;
      state.count = await _totalCount(key);
      _error = null;
      errorResult = null;
    } else if (errorResult == null && !_connectivity.isConnected) {
      errorResult = 'Aucune connexion Internet et page non disponible en cache';
    }

    _isLoading = false;
    notifyListeners();
    return errorResult;
  }

  Future<String?> _prevPage(String key, _VisiteFetcher fetcher, String token) async {
    if (_isLoading) return null;
    final state = _states[key]!;
    if (state.page <= 1) return null;

    _isLoading = true;
    notifyListeners();

    final prevPage = state.page - 1;
    state.items = _scopeToToday(key,
        await _readVisits(key, offset: 0, limit: prevPage * _VisiteListState.pageSize));
    state.page = prevPage;
    state.count = await _totalCount(key);
    _error = null;

    _isLoading = false;
    notifyListeners();
    return null;
  }

  // ── Today ──

  Future<void> loadVisitesToday(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageToday(String token) =>
      _nextPage(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          token);

  Future<String?> prevPageToday(String token) =>
      _prevPage(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          token);

  // ── En cours ──

  Future<void> loadVisitesEnCours(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageEnCours(String token) =>
      _nextPage(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          token);

  Future<String?> prevPageEnCours(String token) =>
      _prevPage(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          token);

  // ── Terminees ──

  Future<void> loadVisitesTerminees(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageTerminees(String token) =>
      _nextPage(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          token);

  Future<String?> prevPageTerminees(String token) =>
      _prevPage(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          token);

  // ── Excedees ──

  Future<void> loadVisitesExcedees(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageExcedees(String token) =>
      _nextPage(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          token);

  Future<String?> prevPageExcedees(String token) =>
      _prevPage(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          token);

  // ── Cache ──

  // ── Base locale des visites ─────────────────────────────────────────────
  //
  // Une visite = une ligne. L'ancien stockage serialisait la liste entiere
  // dans une seule valeur : au-dela de 2 Mo, Android refusait de relire la
  // ligne et la liste devenait invisible (~1 600 visites, ou 7 avec photos).
  // Chaque creation reecrivait aussi toute la liste, d'ou un cout quadratique
  // et l'ecrasement des visites deja saisies.

  bool _localRebuilt = false;

  /// Le mobile ne conserve que la période courante : le serveur reste
  /// l'archive. Sans cela la table grandirait indéfiniment.
  static const int _retentionJours = 30;

  Future<Database> get _rawDb => _db.database;

  Map<String, Object?>? _visiteurRow(Visiteur? v) {
    if (v == null || v.uuid.isEmpty) return null;
    return {
      'uuid': v.uuid,
      'id': v.id,
      'nom': v.nom,
      'prenom': v.prenom,
      'genre': v.genre,
      'telephone': v.telephone,
      'email': v.email,
      'numero_piece': v.numeroPiece,
      'numero_nip': v.numeroNip,
      'nationalite': v.nationalite,
      'profession': v.profession,
      'adresse': v.adresse,
      'piece_identite': v.pieceIdentite,
      'date_naissance': v.dateNaissance,
      'lieu_naissance': v.lieuNaissance,
      'pays_delivrance': v.paysDelivrance,
      'date_delivrance': v.dateDelivrance,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, Object?> _visitRow(Visit v, {required bool local}) {
    return {
      'id': v.id,
      'uuid': v.uuid,
      'visiteur_uuid': v.visiteur?.uuid,
      'est_local': local ? 1 : 0,
      'statut': v.statut,
      'date_visite': v.dateVisite,
      'heure_arrivee': v.heureArrivee,
      'personnel_id': v.personnelId,
      'updated_at': DateTime.now().toIso8601String(),
      'data_json': jsonEncode(v.toJson()),
    };
  }

  Map<String, Object?> _lienRow(String liste, int visitId, int ordre) =>
      {'liste': liste, 'visit_id': visitId, 'ordre': ordre};

  /// Enregistre une visite et, au passage, son visiteur dans le repertoire
  /// local — c'est lui qui rend la recherche par numero de piece possible
  /// sans reseau.
  Future<void> _upsertVisit(DatabaseExecutor db, Visit v,
      {required bool local}) async {
    final visiteur = _visiteurRow(v.visiteur);
    if (visiteur != null) {
      await db.insert('visiteurs', visiteur,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await db.insert('visits', _visitRow(v, local: local),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rattache une visite à une liste, ou met à jour son rang.
  Future<void> _lierAListe(
          DatabaseExecutor db, String liste, int visitId, int ordre) =>
      db.insert('visit_listes', _lienRow(liste, visitId, ordre),
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// Ajoute une visite a un lot d'ecritures. Un lot part en un seul aller-
  /// retour vers SQLite, la ou des insertions une par une en font un par
  /// requete — sur dix mille visites, la difference se compte en dizaines de
  /// secondes.
  void _batchVisit(Batch batch, String liste, Visit v,
      {required bool local, required int ordre}) {
    final visiteur = _visiteurRow(v.visiteur);
    if (visiteur != null) {
      batch.insert('visiteurs', visiteur,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    batch.insert('visits', _visitRow(v, local: local),
        conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('visit_listes', _lienRow(liste, v.id, ordre),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Position a donner a une visite que l'on veut voir arriver en tete de
  /// liste. Persistant : on repart du plus petit ordre deja present.
  Future<int> _headOrdre(DatabaseExecutor db, String liste) async {
    final rows = await db.rawQuery(
        'SELECT MIN(ordre) AS m FROM visit_listes WHERE liste = ?', [liste]);
    final min = rows.first['m'] as int?;
    return (min == null || min > 0) ? -1 : min - 1;
  }

  /// Ecrit une page renvoyee par le serveur, sans toucher aux saisies locales.
  Future<void> _storeServerPage(
      String liste, List<Visit> items, int page, int serverCount) async {
    final db = await _rawDb;
    final start = (page - 1) * _VisiteListState.pageSize;
    final batch = db.batch();
    // On ne retire que les rattachements venant du serveur : les saisies
    // locales gardent leur place en tête de liste.
    batch.delete('visit_listes',
        where: 'liste = ? AND ordre >= ? AND visit_id IN '
            '(SELECT id FROM visits WHERE est_local = 0)',
        whereArgs: [liste, start]);
    for (var i = 0; i < items.length; i++) {
      _batchVisit(batch, liste, items[i], local: false, ordre: start + i);
    }

    batch.insert(
        'visits_meta',
        {
          'liste': liste,
          'server_count': serverCount,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<List<Visit>> _readVisits(String liste,
      {required int offset, required int limit}) async {
    final db = await _rawDb;
    final rows = await db.rawQuery(
        'SELECT v.data_json FROM visit_listes l '
        'JOIN visits v ON v.id = l.visit_id '
        'WHERE l.liste = ? ORDER BY l.ordre ASC LIMIT ? OFFSET ?',
        [liste, limit, offset]);
    final out = <Visit>[];
    for (final row in rows) {
      try {
        out.add(Visit.fromJson(
            jsonDecode(row['data_json'] as String) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[VisitProvider] Visite locale illisible, ignoree : $e');
      }
    }
    return out;
  }

  /// Total a afficher : ce que le serveur annonce, plus les saisies locales
  /// qu'il ne connait pas encore — et jamais moins que ce que la liste
  /// affiche reellement.
  Future<int> _totalCount(String liste) async {
    final db = await _rawDb;
    final meta = await db.query('visits_meta',
        columns: ['server_count'], where: 'liste = ?', whereArgs: [liste], limit: 1);
    final serverCount = meta.isEmpty ? 0 : (meta.first['server_count'] as int? ?? 0);
    final local = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM visit_listes l '
        'JOIN visits v ON v.id = l.visit_id '
        'WHERE l.liste = ? AND v.est_local = 1',
        [liste]);
    final annonce = serverCount + ((local.first['n'] as int?) ?? 0);

    // Une saisie hors ligne qui vient d'etre synchronisee n'est plus locale,
    // et `server_count` — fige au dernier chargement reussi de la liste — ne
    // la compte pas encore. Sans ce garde-fou, les tuiles retombaient a zero
    // au redemarrage alors que la liste, elle, montrait bien la visite.
    final enBase = await _countRowsInList(db, liste);
    return annonce > enBase ? annonce : enBase;
  }

  /// Nombre de visites reellement rattachees a [liste] dans la base locale,
  /// avec le meme perimetre « jour meme » que [_scopeToToday].
  Future<int> _countRowsInList(Database db, String liste) async {
    final rows = _todayScopedKeys.contains(liste)
        ? await db.rawQuery(
            'SELECT COUNT(*) AS n FROM visit_listes l '
            'JOIN visits v ON v.id = l.visit_id '
            'WHERE l.liste = ? AND (v.date_visite IS NULL '
            'OR substr(v.date_visite, 1, 10) = ?)',
            [liste, _todayIso()])
        : await db.rawQuery(
            'SELECT COUNT(*) AS n FROM visit_listes WHERE liste = ?', [liste]);
    return (rows.first['n'] as int?) ?? 0;
  }

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _insertLocalVisit(String liste, Visit v) async {
    final db = await _rawDb;
    await db.transaction((txn) async {
      await _upsertVisit(txn, v, local: true);
      await _lierAListe(txn, liste, v.id, await _headOrdre(txn, liste));
    });
  }

  Future<void> _updateVisitRows(int visiteId, Visit v) async {
    final db = await _rawDb;
    final visiteur = _visiteurRow(v.visiteur);
    await db.transaction((txn) async {
      if (visiteur != null) {
        await txn.insert('visiteurs', visiteur,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
          'visits',
          {
            'visiteur_uuid': v.visiteur?.uuid,
            'statut': v.statut,
            'date_visite': v.dateVisite,
            'heure_arrivee': v.heureArrivee,
            'personnel_id': v.personnelId,
            'updated_at': DateTime.now().toIso8601String(),
            'data_json': jsonEncode(v.toJson()),
          },
          where: 'id = ?',
          whereArgs: [visiteId]);
    });
  }

  /// Détache une visite de certaines listes sans la supprimer.
  Future<void> _delierDesListes(int visitId, List<String> listes) async {
    if (listes.isEmpty) return;
    final db = await _rawDb;
    await db.delete('visit_listes',
        where: 'visit_id = ? AND liste IN (${List.filled(listes.length, '?').join(', ')})',
        whereArgs: [visitId, ...listes]);
  }

  /// Supprime une visite et, par cascade, ses rattachements aux listes.
  Future<void> _deleteVisit({int? id, String? uuid}) async {
    final db = await _rawDb;
    if (id != null) {
      await db.delete('visit_listes', where: 'visit_id = ?', whereArgs: [id]);
      await db.delete('visits', where: 'id = ?', whereArgs: [id]);
      return;
    }
    if (uuid == null) return;
    final rows = await db.query('visits',
        columns: ['id'], where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return;
    final visitId = rows.first['id'] as int;
    await db.delete('visit_listes', where: 'visit_id = ?', whereArgs: [visitId]);
    await db.delete('visits', where: 'id = ?', whereArgs: [visitId]);
  }

  /// Deplace une visite vers « terminees », en tete.
  Future<void> _moveToTerminees(Visit visit, {required bool local}) async {
    final db = await _rawDb;
    await db.transaction((txn) async {
      await txn.delete('visit_listes',
          where: 'visit_id = ? AND liste IN (?, ?, ?)',
          whereArgs: [visit.id, _enCoursKey, _excedeesKey, _todayKey]);
      final terminee = visit.copyWith(statut: 'TERMINEE');
      await _upsertVisit(txn, terminee, local: local);
      await _lierAListe(
          txn, _termineesKey, terminee.id, await _headOrdre(txn, _termineesKey));
    });
  }

  /// Reconstruit les visites hors ligne a partir de la file d'envoi. Sert a la
  /// migration depuis l'ancien stockage — dont le contenu pouvait justement
  /// etre devenu illisible — et de filet de securite : `pending_sync` contient
  /// l'integralite de la saisie, rien n'est perdu.
  Future<void> _rebuildLocalVisitsFromQueue() async {
    if (_localRebuilt) return;
    _localRebuilt = true;
    try {
      final db = await _rawDb;

      // On ne lit que les identifiants : les charges utiles contiennent les
      // photos, les prendre toutes d'un coup remplirait la mémoire.
      final ids = await db.query('pending_sync',
          columns: ['id'],
          where: 'action = ?',
          whereArgs: ['create_visite'],
          orderBy: 'id ASC');

      final known = await db.query('visits', columns: ['uuid'], where: 'est_local = 1');
      final deja = known.map((r) => r['uuid'] as String).toSet();

      // Copies locales dont la création est déjà partie au serveur : périmées.
      final attendus = {for (final r in ids) 'local_${r['id']}'};
      for (final uuid in deja.difference(attendus)) {
        await _deleteVisit(uuid: uuid);
        debugPrint('[VisitProvider] Copie locale périmée retirée : $uuid');
      }

      var restaurees = 0;
      if (ids.isNotEmpty) {
      var ordre = await _headOrdre(db, _enCoursKey);
      var ordreToday = await _headOrdre(db, _todayKey);

      // Traitement par tranches : les charges utiles contiennent les photos,
      // on n'en garde qu'un petit nombre en mémoire à la fois, et chaque
      // tranche part en un seul lot d'écritures.
      const tranche = 200;
      for (var debut = 0; debut < ids.length; debut += tranche) {
        final fin = (debut + tranche < ids.length) ? debut + tranche : ids.length;
        final lot = <int>[
          for (final r in ids.sublist(debut, fin))
            if (!deja.contains('local_${r['id']}')) r['id'] as int
        ];
        if (lot.isEmpty) continue;

        final payloads = await db.query('pending_sync',
            columns: ['id', 'payload'],
            where: 'id IN (${List.filled(lot.length, '?').join(',')})',
            whereArgs: lot,
            orderBy: 'id ASC');

        final batch = db.batch();
        for (final row in payloads) {
          final pendingId = row['id'] as int;
          try {
            final body =
                jsonDecode(row['payload'] as String) as Map<String, dynamic>;
            final visit = _visitFromPayload(pendingId, body);
            _batchVisit(batch, _enCoursKey, visit, local: true, ordre: ordre--);
            if (_isToday(visit.dateVisite ?? '')) {
              batch.insert('visit_listes',
                  _lienRow(_todayKey, visit.id, ordreToday--),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
            restaurees++;
          } catch (e) {
            debugPrint('[VisitProvider] Saisie #$pendingId illisible : $e');
          }
        }
        await batch.commit(noResult: true);
      }

      if (restaurees > 0) {
        debugPrint('[VisitProvider] $restaurees saisie(s) hors ligne restaurée(s) en base locale');
      }
      }
    } catch (e) {
      debugPrint('[VisitProvider] Reconstruction des saisies hors ligne impossible : $e');
    }
    await _purgeAnciennesVisites();
    await _nettoyerImagesOrphelines();
  }

  /// Supprime du disque les images que plus rien ne référence : ni une saisie
  /// en attente, ni une visite encore présente en base locale. Ces dernières
  /// gardent leurs fichiers même une fois synchronisées — c'est la seule copie
  /// consultable hors connexion —, et la purge des visites anciennes finit
  /// donc par libérer le disque.
  Future<void> _nettoyerImagesOrphelines() async {
    try {
      final db = await _rawDb;
      final rows = await db.query('pending_sync', columns: ['payload']);
      final references = <String>[];
      for (final row in rows) {
        try {
          final body =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          for (final cle in VisitMedia.champs.keys) {
            final ref = body[cle] as String?;
            if (ref != null) references.add(ref);
          }
        } catch (_) {}
      }

      // Visites conservées en base : seules celles dont la fiche mentionne une
      // référence locale sont relues, la table pouvant être volumineuse.
      final visites = await db.query('visits',
          columns: ['data_json'],
          where: 'data_json LIKE ?',
          whereArgs: ['%${VisitMedia.scheme}%']);
      for (final row in visites) {
        try {
          final visite = Visit.fromJson(
              jsonDecode(row['data_json'] as String) as Map<String, dynamic>);
          for (final ref in [
            visite.visiteur?.photo,
            visite.visiteur?.documentRecto,
            visite.visiteur?.documentVerso,
          ]) {
            if (ref != null) references.add(ref);
          }
        } catch (_) {}
      }
      final supprimes = await VisitMedia.sweepOrphans(references);
      if (supprimes > 0) {
        debugPrint('[VisitProvider] $supprimes image(s) orpheline(s) supprimée(s)');
      }
    } catch (e) {
      debugPrint('[VisitProvider] Balayage des images impossible : $e');
    }
  }

  /// Supprime les visites du serveur antérieures à la période conservée. Les
  /// saisies locales, elles, ne sont jamais purgées : elles ne sont nulle part
  /// ailleurs tant qu'elles ne sont pas synchronisées.
  Future<void> _purgeAnciennesVisites() async {
    try {
      final db = await _rawDb;
      final limite = DateTime.now().subtract(const Duration(days: _retentionJours));
      final borne = '${limite.year}-'
          '${limite.month.toString().padLeft(2, '0')}-'
          '${limite.day.toString().padLeft(2, '0')}';
      await db.delete('visit_listes',
          where: 'visit_id IN (SELECT id FROM visits WHERE est_local = 0 '
              'AND date_visite IS NOT NULL AND date_visite < ?)',
          whereArgs: [borne]);
      final supprimees = await db.delete('visits',
          where: 'est_local = 0 AND date_visite IS NOT NULL AND date_visite < ?',
          whereArgs: [borne]);
      if (supprimees > 0) {
        debugPrint('[VisitProvider] $supprimees visite(s) de plus de $_retentionJours jours purgée(s)');
        // Sans VACUUM le fichier ne rétrécit pas après une purge importante.
        await db.execute('VACUUM');
      }
    } catch (e) {
      debugPrint('[VisitProvider] Purge des anciennes visites impossible : $e');
    }
  }

  // ── Visit detail ──

  Future<Visit?> getVisitDetail(String token, int visiteId, {Future<bool> Function()? onUnauthorized}) async {
    final fromList = _findInLists(visiteId);
    if (fromList != null) return fromList;

    final cached = await _loadDetailFromCache(visiteId);
    if (cached != null) return cached;

    if (!_connectivity.isConnected) return null;

    try {
      final visit = await _visitService.getVisite(token, visiteId);
      await _saveDetailToCache(visit);
      return visit;
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) return await getVisitDetail(token, visiteId, onUnauthorized: null);
      }
      rethrow;
    }
  }

  Future<Visit?> refreshVisitDetail(String token, int visiteId, {Future<bool> Function()? onUnauthorized}) async {
    if (!_connectivity.isConnected) return null;
    try {
      final visit = await _visitService.getVisite(token, visiteId);
      await _saveDetailToCache(visit);
      return visit;
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) return await refreshVisitDetail(token, visiteId, onUnauthorized: null);
      }
      return null;
    }
  }

  Visit? _findInLists(int visiteId) {
    for (final state in _states.values) {
      final found = state.items.where((v) => v.id == visiteId);
      if (found.isNotEmpty) return found.first;
    }
    return null;
  }

  /// La table `visits` fait office de fiche complète : plus de table de détail
  /// séparée qui stockait une seconde copie de la même visite.
  Future<void> _saveDetailToCache(Visit visit) async {
    final db = await _rawDb;
    await _upsertVisit(db, visit, local: false);
  }

  Future<Visit?> _loadDetailFromCache(int visiteId) => _readVisitById(visiteId);

  // ── Visit CRUD ──

  Future<bool> updateVisite(String token, int visiteId, Map<String, dynamic> body, {Future<bool> Function()? onUnauthorized}) async {
    try {
      final existing = _findInLists(visiteId);
      if (existing != null && existing.uuid.startsWith('local_')) {
        return await _coalesceLocalUpdate(existing, body);
      }

      body['_visite_id'] = visiteId;
      final pendingId = await _db.insert('pending_sync', {
        'action': 'update_visite',
        'payload': jsonEncode(body),
        'created_at': DateTime.now().toIso8601String(),
        'status': 0,
      });

      if (_connectivity.isConnected) {
        try {
          final apiBody = Map<String, dynamic>.from(body)
            ..removeWhere((k, _) => k.startsWith('_'));
          await _visitService.updateVisite(token, visiteId, apiBody);
          await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
        } catch (e) {
          var msg = e.toString();
          if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
            final refreshed = await onUnauthorized();
            if (refreshed) {
              try {
                final apiBody = Map<String, dynamic>.from(body)
                  ..removeWhere((k, _) => k.startsWith('_'));
                await _visitService.updateVisite(token, visiteId, apiBody);
                await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
                msg = '';
              } catch (e2) {
                msg = e2.toString();
              }
            }
          }
          // Le serveur a répondu et a refusé (permission, validation…) : la
          // réessayer indéfiniment ne changera rien, et annoncer un succès
          // serait mentir. La modification est abandonnée et la vraie raison
          // remonte à l'écran. Une panne de réseau, elle, reste en file.
          final refus = RegExp('\\b4\\d\\d\\b').firstMatch(msg);
          if (refus != null && !msg.contains('401')) {
            await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
            _error = 'Le serveur a refusé la modification ($msg)';
            notifyListeners();
            return false;
          }
          if (msg.isNotEmpty) {
            debugPrint('[VisitProvider] Modification réseau échouée, en file d\'attente : $msg');
          }
        }
      }

      await _updateVisitInLists(visiteId, body);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Retire une saisie locale des listes en mémoire et de la base.
  Future<void> _purgeLocalVisit(String localUuid) async {
    for (final state in _states.values) {
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    await _deleteVisit(uuid: localUuid);
  }

  /// Appelée par la synchronisation d'arrière-plan quand une saisie hors
  /// ligne vient d'être créée côté serveur : la copie locale cède la place à
  /// la visite serveur. Sans cela, la copie restait affichée avec son
  /// identifiant local et toute modification échouait (« Échec de
  /// l'enregistrement local » alors que la connexion était bonne).
  Future<void> adoptServerVisit(int pendingId, Visit visit,
      {required bool terminee, Map<String, dynamic>? payload}) async {
    try {
      // Les fichiers restés sur l'appareil suivent la visite : sinon sa fiche
      // n'affichait plus aucune image dès le retour hors connexion.
      final adoptee =
          payload == null ? visit : _conserverImagesLocales(visit, payload);
      if (terminee) {
        await _replacePendingVisitWithTerminated(pendingId, adoptee);
      } else {
        await _replacePendingVisit(pendingId, adoptee);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[VisitProvider] Adoption de la visite #${visit.id} impossible : $e');
    }
  }

  Future<bool> _coalesceLocalUpdate(Visit existing, Map<String, dynamic> body) async {
    try {
      final localId = int.tryParse(existing.uuid.substring(6));
      if (localId == null) return false;

      final rows = await _db.query('pending_sync', where: 'id = ?', whereArgs: [localId], limit: 1);
      if (rows.isEmpty) {
        // La création vient d'être envoyée au serveur : cette copie locale
        // est périmée. On la retire pour que la liste montre la version
        // serveur, sur laquelle la modification pourra être refaite.
        await _purgeLocalVisit(existing.uuid);
        _error =
            'Cette visite vient d\'être synchronisée. Rouvrez-la depuis la liste pour la modifier.';
        notifyListeners();
        return false;
      }

      final createPayload =
          jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
      final editBody = Map<String, dynamic>.from(body)..remove('_visite_id');
      createPayload.addAll(editBody);
      await _db.update('pending_sync', {'payload': jsonEncode(createPayload)},
          where: 'id = ?', whereArgs: [localId]);

      await _updateVisitInLists(existing.id, body);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Visit _applyUpdate(Visit old, Map<String, dynamic> body) {
    return old.copyWith(
      motif: body['motif'] as String? ?? old.motif,
      observations: body['observations'] as String? ?? old.observations,
      numeroBadge: body['numero_badge'] as String? ?? old.numeroBadge,
      dateVisite: body['date_visite'] as String? ?? old.dateVisite,
      heureArrivee: body['heure_arrivee'] as String? ?? old.heureArrivee,
      dateExpiration: body['date_expiration'] as String? ?? old.dateExpiration,
      typeVisiteId: body['type_visite_id'] as int? ?? old.typeVisiteId,
      // L'objet affiche n'est remplace que si la modification apporte son
      // libelle : sans cela, un nom deja connu serait efface.
      typeVisite: body.containsKey('_type_visite_nom')
          ? _typeVisiteFromBody(body)
          : old.typeVisite,
      porteEntreeId: body['porte_entree_id'] as int? ?? old.porteEntreeId,
      porteEntree: body.containsKey('_porte_entree_titre')
          ? _porteFromBody(body)
          : old.porteEntree,
      personnelId: body['personnel_id'] as int? ?? old.personnelId,
      personnel: body.containsKey('_personnel_nom')
          ? _personnelFromBody(body)
          : old.personnel,
      visiteur: _updatedVisiteur(old.visiteur, body),
    );
  }

  Future<void> _updateVisitInLists(int visiteId, Map<String, dynamic> body) async {
    Visit? updated;
    for (final state in _states.values) {
      final idx = state.items.indexWhere((v) => v.id == visiteId);
      if (idx == -1) continue;
      updated = _applyUpdate(state.items[idx], body);
      state.items[idx] = updated;
    }

    // La visite peut n'être dans aucune liste chargée en mémoire : on la
    // reprend alors depuis la base locale.
    if (updated == null) {
      final stored = await _readVisitById(visiteId);
      if (stored == null) return;
      updated = _applyUpdate(stored, body);
    }

    // Une seule ligne est réécrite, quelle que soit la taille des listes.
    await _updateVisitRows(visiteId, updated);
  }

  /// Recherche un visiteur dans le répertoire local, par numéro de pièce ou
  /// par NIP. C'est ce qui permet de pré-remplir nationalité et téléphone
  /// sans réseau, à partir des visites déjà enregistrées sur l'appareil.
  Future<Map<String, dynamic>?> findVisiteurLocal(String query) async {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return null;
    try {
      final db = await _rawDb;
      final rows = await db.query('visiteurs',
          where: 'UPPER(numero_piece) = ? OR UPPER(numero_nip) = ?',
          whereArgs: [q, q],
          orderBy: 'updated_at DESC',
          limit: 1);
      return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
    } catch (e) {
      debugPrint('[VisitProvider] Recherche locale du visiteur impossible : $e');
      return null;
    }
  }

  Future<Visit?> _readVisitById(int visiteId) async {
    final db = await _rawDb;
    final rows = await db.query('visits',
        columns: ['data_json'], where: 'id = ?', whereArgs: [visiteId], limit: 1);
    if (rows.isEmpty) return null;
    try {
      return Visit.fromJson(
          jsonDecode(rows.first['data_json'] as String) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Visiteur? _updatedVisiteur(Visiteur? v, Map<String, dynamic> body) {
    if (v == null) return v;
    return Visiteur(
      id: v.id,
      uuid: v.uuid,
      nom: body['v_nom'] as String? ?? v.nom,
      prenom: body['v_prenom'] as String? ?? v.prenom,
      genre: body['v_genre'] as String? ?? v.genre,
      telephone: body['v_telephone'] as String? ?? v.telephone,
      email: body['v_email'] as String? ?? v.email,
      numeroPiece: body['v_numero_piece'] as String? ?? v.numeroPiece,
      numeroNip: body['v_nip'] as String? ?? v.numeroNip,
      nationalite: body['v_nationalite'] as String? ?? v.nationalite,
      profession: body['v_profession'] as String? ?? v.profession,
      adresse: body['v_adresse'] as String? ?? v.adresse,
      pieceIdentite: body['v_piece_identite'] as String? ?? v.pieceIdentite,
      dateNaissance: body['v_date_naissance'] as String? ?? v.dateNaissance,
      lieuNaissance: body['v_lieu_naissance'] as String? ?? v.lieuNaissance,
      paysDelivrance: body['v_pays_delivrance'] as String? ?? v.paysDelivrance,
      dateDelivrance: body['v_date_delivrance'] as String? ?? v.dateDelivrance,
      photo: v.photo,
      documentRecto: v.documentRecto,
      documentVerso: v.documentVerso,
      statut: v.statut,
    );
  }

  Future<void> createVisite(String token, Map<String, dynamic> body, {Future<bool> Function()? onUnauthorized}) async {
    final pendingId = await _db.insert('pending_sync', {
      'action': 'create_visite',
      'payload': jsonEncode(body),
      'created_at': DateTime.now().toIso8601String(),
      'status': 0,
    });

    await _addLocalPendingVisit(pendingId, body);

    if (_connectivity.isConnected) {
      _tryCreateOnline(token, pendingId, onUnauthorized);
    }
  }

  Future<void> _addLocalPendingVisit(int pendingId, Map<String, dynamic> body) =>
      _storeLocalVisit(pendingId, body);

  /// Les libellés saisis dans le formulaire voyagent avec la charge utile
  /// (clés privées, préfixe `_`) : sans eux, la fiche d'une visite hors ligne
  /// n'afficherait ni la porte d'entrée, ni le personnel, ni le type de
  /// visite — leurs objets ne sont autrement connus que du serveur.
  TypeVisite? _typeVisiteFromBody(Map<String, dynamic> body) {
    final id = body['type_visite_id'] as int?;
    if (id == null) return null;
    return TypeVisite(
      id: id,
      uuid: '',
      nom: body['_type_visite_nom'] as String?,
      description: body['_type_visite_description'] as String?,
    );
  }

  PorteEntree? _porteFromBody(Map<String, dynamic> body) {
    final id = body['porte_entree_id'] as int?;
    if (id == null) return null;
    return PorteEntree(
      id: id,
      titre: body['_porte_entree_titre'] as String?,
      emplacement: body['_porte_entree_emplacement'] as String?,
    );
  }

  Personnel? _personnelFromBody(Map<String, dynamic> body) {
    final id = body['personnel_id'] as int?;
    if (id == null) return null;
    return Personnel(
      id: id,
      nom: body['_personnel_nom'] as String?,
      prenom: body['_personnel_prenom'] as String?,
      fonction: body['_personnel_fonction'] as String?,
      departement: body['_personnel_departement'] as String?,
      departementId: body['departement_id'] as int?,
    );
  }

  /// Reconstruit la visite correspondant à une saisie hors ligne.
  /// `pending_sync` en détient la source complète : elle peut être rebâtie à
  /// tout moment, y compris après une migration.
  Visit _visitFromPayload(int pendingId, Map<String, dynamic> body) {
    final uuid = 'local_$pendingId';
    final now = DateTime.now();
    final dateVisite = body['date_visite'] as String? ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return Visit(
      id: -pendingId,
      uuid: uuid,
      statut: (body['statut'] as String?) ?? 'EN_COURS',
      genre: body['genre'] as String?,
      typeVisiteId: body['type_visite_id'] as int?,
      typeVisite: _typeVisiteFromBody(body),
      porteEntreeId: body['porte_entree_id'] as int?,
      porteEntree: _porteFromBody(body),
      personnelId: body['personnel_id'] as int?,
      personnel: _personnelFromBody(body),
      dateVisite: dateVisite,
      heureArrivee: (body['heure_arrivee'] as String?) ?? '00:00',
      dateExpiration: body['date_expiration'] as String?,
      numeroBadge: body['numero_badge'] as String?,
      motif: body['motif'] as String?,
      observations: body['observations'] as String?,
      signatureEntree: body['signature_entree'] as String?,
      visiteur: Visiteur(
        id: -pendingId,
        uuid: uuid,
        nom: body['v_nom'] as String?,
        prenom: body['v_prenom'] as String?,
        genre: body['v_genre'] as String? ?? body['genre'] as String?,
        telephone: body['v_telephone'] as String?,
        email: body['v_email'] as String?,
        numeroPiece: body['v_numero_piece'] as String?,
        numeroNip: body['v_nip'] as String?,
        nationalite: body['v_nationalite'] as String?,
        profession: body['v_profession'] as String?,
        adresse: body['v_adresse'] as String?,
        pieceIdentite: body['v_piece_identite'] as String?,
        dateNaissance: body['v_date_naissance'] as String?,
        lieuNaissance: body['v_lieu_naissance'] as String?,
        paysDelivrance: body['v_pays_delivrance'] as String?,
        dateDelivrance: body['v_date_delivrance'] as String?,
        // Références de fichiers, pas de base64 : une ligne de visite pèse
        // quelques kilo-octets au lieu de plusieurs centaines.
        photo: body['photo_path'] as String?,
        documentRecto: body['document_recto_path'] as String?,
        documentVerso: body['document_verso_path'] as String?,
      ),
    );

  }

  /// Enregistre la saisie dans la base locale : un `INSERT` d'une ligne, au
  /// lieu de la réécriture de la liste entière qui effaçait les visites déjà
  /// saisies quand la liste n'avait pas été ouverte.
  Future<void> _storeLocalVisit(int pendingId, Map<String, dynamic> body,
      {bool notify = true}) async {
    final visit = _visitFromPayload(pendingId, body);

    await _insertLocalVisit(_enCoursKey, visit);
    _insertInState(_enCoursKey, visit);

    if (_isToday(visit.dateVisite ?? '')) {
      await _insertLocalVisit(_todayKey, visit);
      _insertInState(_todayKey, visit);
    }
    if (notify) notifyListeners();
  }

  void _insertInState(String key, Visit visit) {
    final state = _states[key]!;
    if (state.items.any((v) => v.uuid == visit.uuid)) return;
    state.items.insert(0, visit);
    state.count++;
  }

  bool _isToday(String dateVisite) {
    final now = DateTime.now();
    final d = DateTime.tryParse(dateVisite);
    if (d == null) return false;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Greffe sur une visite renvoyee par le serveur les images restees sur
  /// l'appareil. Elles ne sont plus effacees apres l'envoi : c'est la seule
  /// copie consultable hors connexion, le serveur ne servant les siennes que
  /// par le reseau. Le balayage des orphelines les retirera quand la visite
  /// elle-meme quittera la base locale.
  Visit _conserverImagesLocales(Visit visit, Map<String, dynamic> payload) {
    final photo = payload['photo_path'] as String?;
    final recto = payload['document_recto_path'] as String?;
    final verso = payload['document_verso_path'] as String?;
    final visiteur = visit.visiteur;
    if (visiteur == null ||
        (!VisitMedia.isLocal(photo) &&
            !VisitMedia.isLocal(recto) &&
            !VisitMedia.isLocal(verso))) {
      return visit;
    }
    return visit.copyWith(
      visiteur: visiteur.copyWithImages(
        photo: VisitMedia.isLocal(photo) ? photo : null,
        documentRecto: VisitMedia.isLocal(recto) ? recto : null,
        documentVerso: VisitMedia.isLocal(verso) ? verso : null,
      ),
    );
  }

  Future<void> _tryCreateOnline(String token, int pendingId,
      Future<bool> Function()? onUnauthorized) async {
    try {
      final rows = await _db.query('pending_sync',
          where: 'id = ?', whereArgs: [pendingId], limit: 1);
      if (rows.isEmpty) return;

      final payload = jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
      final terminerApres = payload.remove('_terminer_apres_creation') == true;
      final terminationBody = payload.remove('_termination_body') as Map<String, dynamic>?;

      // Les images sont encodées ici seulement, le temps de l'envoi.
      final cree = await _visitService.createVisite(
          token, await VisitMedia.toApiBody(payload));
      // Les fichiers restent sur l'appareil et suivent la visite : sans eux,
      // la fiche d'une visite tout juste synchronisee n'affichait plus aucune
      // image des qu'on repassait hors connexion.
      final visit = _conserverImagesLocales(cree, payload);

      if (terminerApres) {
        try {
          await _visitService.terminerVisite(token, visit.id, body: terminationBody);
        } catch (e) {
          debugPrint('[VisitProvider] Clôture après création échouée, rejetée : $e');
          await _db.insert('pending_sync', {
            'action': 'terminer_visite',
            'payload': jsonEncode({
              '_visite_id': visit.id,
              ...?terminationBody,
            }),
            'created_at': DateTime.now().toIso8601String(),
            'status': 0,
          });
        }
        await _replacePendingVisitWithTerminated(pendingId, visit);
      } else {
        await _replacePendingVisit(pendingId, visit);
      }
      await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) {
          _tryCreateOnline(token, pendingId, null);
          return;
        }
      }
      debugPrint('[VisitProvider] Création en arrière-plan échouée, en file d\'attente : $e');
    }
  }

  Future<void> _replacePendingVisit(int pendingId, Visit visit) async {
    final localUuid = 'local_$pendingId';
    for (final state in _states.values) {
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    // La saisie locale cède la place à la visite créée côté serveur.
    await _deleteVisit(uuid: localUuid);
    await _addCreatedVisit(visit);
  }

  Future<void> _replacePendingVisitWithTerminated(int pendingId, Visit visit) async {
    final localUuid = 'local_$pendingId';
    for (final state in _states.values) {
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    await _deleteVisit(uuid: localUuid);
    await _moveToTerminees(visit, local: false);
    final terminees = _states[_termineesKey]!;
    terminees.items.insert(0, visit.copyWith(statut: 'TERMINEE'));
    terminees.count++;
    notifyListeners();
  }

  Future<void> _addCreatedVisit(Visit visit) async {
    final db = await _rawDb;
    final aujourdhui = _isToday(visit.dateVisite ?? '');
    await db.transaction((txn) async {
      await _upsertVisit(txn, visit, local: false);
      await _lierAListe(
          txn, _enCoursKey, visit.id, await _headOrdre(txn, _enCoursKey));
      if (aujourdhui) {
        await _lierAListe(
            txn, _todayKey, visit.id, await _headOrdre(txn, _todayKey));
      }
    });
    _insertInState(_enCoursKey, visit);
    if (aujourdhui) _insertInState(_todayKey, visit);
    notifyListeners();
  }

  Future<bool> _terminerLocalPending(Visit visit, {Map<String, dynamic>? body}) async {
    try {
      final localId = int.tryParse(visit.uuid.substring(6));

      for (final key in [_enCoursKey, _excedeesKey, _todayKey]) {
        final state = _states[key]!;
        final before = state.items.length;
        state.items.removeWhere((v) => v.uuid == visit.uuid);
        if (state.items.length != before && state.count > 0) state.count--;
      }

      final terminees = _states[_termineesKey]!;
      terminees.items.insert(0, visit.copyWith(statut: 'TERMINEE'));
      terminees.count++;

      await _moveToTerminees(visit, local: true);

      if (localId != null) {
        final rows = await _db.query('pending_sync', where: 'id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final createPayload = jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
          createPayload['_terminer_apres_creation'] = true;
          createPayload['_termination_body'] = body ?? {};
          await _db.update('pending_sync', {'payload': jsonEncode(createPayload)},
              where: 'id = ?', whereArgs: [localId]);
        }
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Garantit que les saisies hors ligne figurent dans la base locale, même
  /// si aucune liste n'a encore été ouverte.
  Future<void> ensureLocalVisitsLoaded() => _rebuildLocalVisitsFromQueue();

  /// Total connu pour une liste (`today`, `en_cours`, `terminees`,
  /// `excedees`) : le même chiffre que l'en-tête « N élément(s) » de l'écran
  /// correspondant (compte serveur en cache + saisies locales non
  /// synchronisées). Sert aux tuiles du tableau de bord.
  Future<int> getListTotalCount(String liste) => _totalCount(liste);

  /// Historique des visites d'un même visiteur, la plus récente en tête.
  ///
  /// La base locale fait foi — l'écran de détail reste donc lisible hors
  /// connexion — et, si le réseau est là, une page serveur filtrée sur le
  /// visiteur vient la compléter. Les visites renvoyées par le serveur sont
  /// systématiquement revérifiées côté client : si l'API ignorait le filtre,
  /// l'historique afficherait sinon les visites d'autres personnes.
  Future<List<Visit>> getHistoriqueVisiteur(
    String? token, {
    required String visiteurUuid,
    int? visiteurId,
  }) async {
    final parId = <int, Visit>{};

    try {
      final db = await _rawDb;
      final rows = await db.query('visits',
          columns: ['data_json'],
          where: 'visiteur_uuid = ?',
          whereArgs: [visiteurUuid]);
      for (final row in rows) {
        try {
          final v = Visit.fromJson(
              jsonDecode(row['data_json'] as String) as Map<String, dynamic>);
          parId[v.id] = v;
        } catch (e) {
          debugPrint('[VisitProvider] Visite illisible dans l\'historique : $e');
        }
      }
    } catch (e) {
      debugPrint('[VisitProvider] Historique local indisponible : $e');
    }

    if (token != null && token.isNotEmpty && _connectivity.isConnected) {
      try {
        final result =
            await _visitService.getVisites(token, page: 1, visiteurId: visiteurId);
        for (final v in result.items) {
          if (v.visiteur?.uuid == visiteurUuid ||
              (visiteurId != null && v.visiteur?.id == visiteurId)) {
            parId[v.id] = v;
          }
        }
      } catch (e) {
        debugPrint('[VisitProvider] Historique serveur indisponible : $e');
      }
    }

    String cle(Visit v) => '${v.dateVisite ?? ''} ${v.heureArrivee ?? ''}';
    return parId.values.toList()..sort((a, b) => cle(b).compareTo(cle(a)));
  }

  Future<void> removeLocalPendingVisit(int pendingId) async {
    final localUuid = 'local_$pendingId';
    for (final key in [_enCoursKey, _excedeesKey, _todayKey, _termineesKey]) {
      final state = _states[key]!;
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    await _deleteVisit(uuid: localUuid);
    notifyListeners();
  }

  // ── Sync ──

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    return await _db.query('pending_sync', where: 'status = ?', whereArgs: [0], orderBy: 'id ASC');
  }

  Future<void> markSynced(int pendingId) async {
    await _db.update('pending_sync', {'status': 1}, where: 'id = ?', whereArgs: [pendingId]);
  }

  Future<bool> terminerVisite(String token, int visiteId, {Map<String, dynamic>? body, Future<bool> Function()? onUnauthorized}) async {
    try {
      final pendingVisit = _findInLists(visiteId);
      if (pendingVisit != null && pendingVisit.uuid.startsWith('local_')) {
        return await _terminerLocalPending(pendingVisit, body: body);
      }

      final payload = Map<String, dynamic>.from(body ?? {})..['_visite_id'] = visiteId;
      final pendingId = await _db.insert('pending_sync', {
        'action': 'terminer_visite',
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 0,
      });

      final visit = _findInLists(visiteId);

      for (final key in [_enCoursKey, _excedeesKey, _todayKey]) {
        final state = _states[key]!;
        state.items.removeWhere((v) => v.id == visiteId);
        if (state.count > 0) state.count--;
      }

      if (visit != null) {
        final terminees = _states[_termineesKey]!;
        terminees.items.insert(0, visit.copyWith(statut: 'TERMINEE'));
        terminees.count++;
      }

      // La visite peut ne pas etre en memoire : on la reprend en base pour la
      // deplacer vraiment vers « terminees » plutot que de la faire disparaître.
      final stored = visit ?? await _readVisitById(visiteId);
      if (stored != null) {
        await _moveToTerminees(stored, local: false);
      } else {
        await _delierDesListes(
            visiteId, [_enCoursKey, _excedeesKey, _todayKey]);
      }
      notifyListeners();

      if (_connectivity.isConnected) {
        try {
          await _visitService.terminerVisite(token, visiteId, body: body);
          await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
        } catch (e) {
          final msg = e.toString();
          if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
            final refreshed = await onUnauthorized();
            if (refreshed) {
              try {
                await _visitService.terminerVisite(token, visiteId, body: body);
                await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
              } catch (_) {}
            }
          }
          debugPrint('[VisitProvider] Clôture réseau échouée, en file d\'attente : $e');
        }
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
