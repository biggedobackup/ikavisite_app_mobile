import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/visit.dart';
import '../services/visit_service.dart';
import '../services/cancel_token.dart';
import 'connectivity_provider.dart';

typedef _VisiteFetcher = Future<VisitListResponse> Function(int page);

class _VisiteListState {
  List<Visit> items = [];
  int page = 1;
  int count = 0;

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

  VisitProvider(this._connectivity);

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

  Future<void> _loadList(String key, _VisiteFetcher fetcher, String cacheType,
      String token, {Future<bool> Function()? onUnauthorized}) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final state = _states[key]!;
    state.page = 1;
    _error = null;

    final cached = await _loadFromCache(cacheType, 1);
    if (cached != null) {
      state.items = _parseVisits(cached['items']);
      state.count = cached['count'] as int? ?? 0;
      notifyListeners(); // Affiche le cache immédiatement
    }

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
      state.items = result.items;
      state.count = result.count;
      _error = null;
      await _saveToCache(cacheType, 1, result.items, result.count);

      // Préchargement en arrière-plan des pages suivantes si connecté
      if (result.count > _VisiteListState.pageSize) {
        final totalP = (result.count / _VisiteListState.pageSize).ceil();
        final maxPrefetch = totalP.clamp(1, 5); // Limiter à la page 5 max
        for (int p = 2; p <= maxPrefetch; p++) {
          _prefetchPageInBackground(fetcher, cacheType, p);
        }
      }
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) {
          _isRefreshing = false;
          await _loadList(key, fetcher, cacheType, token);
          return;
        }
      }
      if (state.items.isEmpty) _error = msg;
    }

    _isRefreshing = false;
    notifyListeners();
  }

  void _prefetchPageInBackground(_VisiteFetcher fetcher, String cacheType, int page) async {
    try {
      if (!_connectivity.isConnected) return;
      final result = await fetcher(page);
      await _saveToCache(cacheType, page, result.items, result.count);
      debugPrint('[VisitProvider] Préchargement en arrière-plan réussi pour $cacheType page $page');
    } catch (e) {
      debugPrint('[VisitProvider] Échec du préchargement en arrière-plan pour $cacheType page $page : $e');
    }
  }

  Future<String?> _nextPage(String key, _VisiteFetcher fetcher, String cacheType, String token) async {
    if (_isLoading) return null;
    final state = _states[key]!;
    if (state.page >= state.totalPages) return null;

    _isLoading = true;
    notifyListeners();

    String? errorResult;

    if (_connectivity.isConnected) {
      try {
        final result = await fetcher(state.page + 1);
        state.items = [...state.items, ...result.items]; // Concatène les nouveaux éléments
        state.page++;
        state.count = result.count;
        _error = null;
        await _saveToCache(cacheType, state.page, result.items, result.count);
      } catch (e) {
        _error = e.toString();
        errorResult = _error;
      }
    } else {
      final cached = await _loadFromCache(cacheType, state.page + 1);
      if (cached != null) {
        state.items = [...state.items, ..._parseVisits(cached['items'])]; // Concatène les nouveaux éléments du cache
        state.count = cached['count'] as int? ?? 0;
        state.page++;
        _error = null;
      } else {
        errorResult = 'Aucune connexion Internet et page non disponible en cache';
      }
    }

    _isLoading = false;
    notifyListeners();
    return errorResult;
  }

  Future<String?> _prevPage(String key, _VisiteFetcher fetcher, String cacheType, String token) async {
    if (_isLoading) return null;
    final state = _states[key]!;
    if (state.page <= 1) return null;

    _isLoading = true;
    notifyListeners();

    String? errorResult;

    if (_connectivity.isConnected) {
      try {
        final result = await fetcher(state.page - 1);
        state.items = result.items;
        state.page--;
        state.count = result.count;
        _error = null;
        await _saveToCache(cacheType, state.page, result.items, result.count);
      } catch (e) {
        _error = e.toString();
        errorResult = _error;
      }
    } else {
      final cached = await _loadFromCache(cacheType, state.page - 1);
      if (cached != null) {
        state.items = _parseVisits(cached['items']);
        state.count = cached['count'] as int? ?? 0;
        state.page--;
        _error = null;
      } else {
        errorResult = 'Aucune connexion Internet et page non disponible en cache';
      }
    }

    _isLoading = false;
    notifyListeners();
    return errorResult;
  }

  // ── Today ──

  Future<void> loadVisitesToday(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          'today_v2', token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageToday(String token) =>
      _nextPage(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          'today_v2', token);

  Future<String?> prevPageToday(String token) =>
      _prevPage(_todayKey, (p) => _visitService.getVisites(token, page: p, aujourdhui: true),
          'today_v2', token);

  // ── En cours ──

  Future<void> loadVisitesEnCours(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          'en_cours', token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageEnCours(String token) =>
      _nextPage(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          'en_cours', token);

  Future<String?> prevPageEnCours(String token) =>
      _prevPage(_enCoursKey, (p) => _visitService.getVisitesEnCours(token, page: p),
          'en_cours', token);

  // ── Terminees ──

  Future<void> loadVisitesTerminees(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          'terminees', token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageTerminees(String token) =>
      _nextPage(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          'terminees', token);

  Future<String?> prevPageTerminees(String token) =>
      _prevPage(_termineesKey, (p) => _visitService.getVisitesTerminees(token, page: p),
          'terminees', token);

  // ── Excedees ──

  Future<void> loadVisitesExcedees(String token, {Future<bool> Function()? onUnauthorized}) =>
      _loadList(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          'excedees', token, onUnauthorized: onUnauthorized);

  Future<String?> nextPageExcedees(String token) =>
      _nextPage(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          'excedees', token);

  Future<String?> prevPageExcedees(String token) =>
      _prevPage(_excedeesKey, (p) => _visitService.getVisitesExcedees(token, page: p),
          'excedees', token);

  // ── Cache ──

  Future<void> _saveToCache(String cacheType, int page, List<Visit> items, int count) async {
    final existing = await _db.query('visits_cache',
        where: 'cache_type = ? AND page = ?', whereArgs: [cacheType, page]);
    final data = jsonEncode({'items': items.map((v) => v.toJson()).toList(), 'count': count});
    if (existing.isNotEmpty) {
      await _db.update('visits_cache', {'data_json': data, 'count': count, 'updated_at': DateTime.now().toIso8601String()},
          where: 'cache_type = ? AND page = ?', whereArgs: [cacheType, page]);
    } else {
      await _db.insert('visits_cache', {'cache_type': cacheType, 'page': page, 'data_json': data, 'count': count, 'updated_at': DateTime.now().toIso8601String()});
    }
  }

  Future<Map<String, dynamic>?> _loadFromCache(String cacheType, int page) async {
    final result = await _db.query('visits_cache',
        where: 'cache_type = ? AND page = ?', whereArgs: [cacheType, page], limit: 1);
    if (result.isEmpty) return null;
    return jsonDecode(result.first['data_json'] as String) as Map<String, dynamic>;
  }

  List<Visit> _parseVisits(dynamic items) {
    return (items as List).map((e) => Visit.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<void> _saveDetailToCache(Visit visit) async {
    final existing = await _db.query('visit_detail_cache', where: 'id = ?', whereArgs: [visit.id], limit: 1);
    final data = {'data_json': jsonEncode(visit.toJson()), 'updated_at': DateTime.now().toIso8601String()};
    if (existing.isNotEmpty) {
      await _db.update('visit_detail_cache', data, where: 'id = ?', whereArgs: [visit.id]);
    } else {
      await _db.insert('visit_detail_cache', {...data, 'id': visit.id});
    }
  }

  Future<Visit?> _loadDetailFromCache(int visiteId) async {
    final result = await _db.query('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId], limit: 1);
    if (result.isEmpty) return null;
    return Visit.fromJson(jsonDecode(result.first['data_json'] as String) as Map<String, dynamic>);
  }

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

      await _updateVisitInLists(visiteId, body);
      await _db.delete('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId]);

      if (_connectivity.isConnected) {
        try {
          final apiBody = Map<String, dynamic>.from(body)..remove('_visite_id');
          await _visitService.updateVisite(token, visiteId, apiBody);
          await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
        } catch (e) {
          final msg = e.toString();
          if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
            final refreshed = await onUnauthorized();
            if (refreshed) {
              try {
                final apiBody = Map<String, dynamic>.from(body)..remove('_visite_id');
                await _visitService.updateVisite(token, visiteId, apiBody);
                await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
              } catch (_) {}
            }
          }
          debugPrint('[VisitProvider] Modification réseau échouée, en file d\'attente : $e');
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

  Future<bool> _coalesceLocalUpdate(Visit existing, Map<String, dynamic> body) async {
    try {
      final localId = int.tryParse(existing.uuid.substring(6));
      if (localId == null) return false;

      final rows = await _db.query('pending_sync', where: 'id = ?', whereArgs: [localId], limit: 1);
      if (rows.isEmpty) return false;

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

  Future<void> _updateVisitInLists(int visiteId, Map<String, dynamic> body) async {
    for (final state in _states.values) {
      final idx = state.items.indexWhere((v) => v.id == visiteId);
      if (idx == -1) continue;
      final old = state.items[idx];
      state.items[idx] = old.copyWith(
        motif: body['motif'] as String? ?? old.motif,
        observations: body['observations'] as String? ?? old.observations,
        numeroBadge: body['numero_badge'] as String? ?? old.numeroBadge,
        dateVisite: body['date_visite'] as String? ?? old.dateVisite,
        heureArrivee: body['heure_arrivee'] as String? ?? old.heureArrivee,
        dateExpiration: body['date_expiration'] as String? ?? old.dateExpiration,
        typeVisiteId: body['type_visite_id'] as int? ?? old.typeVisiteId,
        porteEntreeId: body['porte_entree_id'] as int? ?? old.porteEntreeId,
        personnelId: body['personnel_id'] as int? ?? old.personnelId,
        visiteur: _updatedVisiteur(old.visiteur, body),
      );
    }
    for (final entry in _states.entries) {
      await _saveToCache(entry.key, entry.value.page, entry.value.items, entry.value.count);
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

  Future<void> _addLocalPendingVisit(int pendingId, Map<String, dynamic> body) async {
    final uuid = 'local_$pendingId';
    final now = DateTime.now();
    final dateVisite = body['date_visite'] as String? ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final visit = Visit(
      id: -pendingId,
      uuid: uuid,
      statut: (body['statut'] as String?) ?? 'EN_COURS',
      genre: body['genre'] as String?,
      typeVisiteId: body['type_visite_id'] as int?,
      porteEntreeId: body['porte_entree_id'] as int?,
      personnelId: body['personnel_id'] as int?,
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
        photo: body['photo_base64'] as String?,
        documentRecto: body['document_recto_base64'] as String?,
        documentVerso: body['document_verso_base64'] as String?,
      ),
    );

    final enCours = _states[_enCoursKey]!;
    enCours.items.insert(0, visit);
    enCours.count++;
    await _saveToCache('en_cours', enCours.page, enCours.items, enCours.count);

    if (_isToday(dateVisite)) {
      final todayState = _states[_todayKey]!;
      todayState.items.insert(0, visit);
      todayState.count++;
      await _saveToCache('today_v2', todayState.page, todayState.items, todayState.count);
    }
    notifyListeners();
  }

  bool _isToday(String dateVisite) {
    final now = DateTime.now();
    final d = DateTime.tryParse(dateVisite);
    if (d == null) return false;
    return d.year == now.year && d.month == now.month && d.day == now.day;
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

      final visit = await _visitService.createVisite(token, payload);

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
    await _addCreatedVisit(visit);
  }

  Future<void> _replacePendingVisitWithTerminated(int pendingId, Visit visit) async {
    final localUuid = 'local_$pendingId';
    for (final state in _states.values) {
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    final terminees = _states[_termineesKey]!;
    terminees.items.insert(0, visit.copyWith(statut: 'TERMINEE'));
    terminees.count++;
    await _saveToCache('terminees', terminees.page, terminees.items, terminees.count);
    notifyListeners();
  }

  Future<void> _addCreatedVisit(Visit visit) async {
    final enCours = _states[_enCoursKey]!;
    enCours.items.insert(0, visit);
    enCours.count++;
    await _saveToCache('en_cours', enCours.page, enCours.items, enCours.count);

    if (visit.dateVisite != null) {
      final today = DateTime.now();
      final visitDate = DateTime.tryParse(visit.dateVisite!);
      if (visitDate != null &&
          visitDate.year == today.year &&
          visitDate.month == today.month &&
          visitDate.day == today.day) {
        final todayState = _states[_todayKey]!;
        todayState.items.insert(0, visit);
        todayState.count++;
        await _saveToCache('today_v2', todayState.page, todayState.items, todayState.count);
      }
    }
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

      await _saveToCache('en_cours', _states[_enCoursKey]!.page, _states[_enCoursKey]!.items, _states[_enCoursKey]!.count);
      await _saveToCache('excedees', _states[_excedeesKey]!.page, _states[_excedeesKey]!.items, _states[_excedeesKey]!.count);
      await _saveToCache('today_v2', _states[_todayKey]!.page, _states[_todayKey]!.items, _states[_todayKey]!.count);
      await _saveToCache('terminees', terminees.page, terminees.items, terminees.count);

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

  Future<int> getLocalPendingVisitsCount() async {
    final state = _states[_enCoursKey]!;
    if (state.items.isNotEmpty) {
      return state.items.where((v) => v.uuid.startsWith('local_')).length;
    }
    final cached = await _loadFromCache('en_cours', 1);
    if (cached == null) return 0;
    return _parseVisits(cached['items'])
        .where((v) => v.uuid.startsWith('local_'))
        .length;
  }

  Future<void> removeLocalPendingVisit(int pendingId) async {
    final localUuid = 'local_$pendingId';
    for (final key in [_enCoursKey, _excedeesKey, _todayKey, _termineesKey]) {
      final state = _states[key]!;
      final before = state.items.length;
      state.items.removeWhere((v) => v.uuid == localUuid);
      if (state.items.length != before && state.count > 0) state.count--;
    }
    for (final entry in _states.entries) {
      await _saveToCache(entry.key, entry.value.page, entry.value.items, entry.value.count);
    }
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

      await _saveToCache('en_cours', _states[_enCoursKey]!.page, _states[_enCoursKey]!.items, _states[_enCoursKey]!.count);
      await _saveToCache('excedees', _states[_excedeesKey]!.page, _states[_excedeesKey]!.items, _states[_excedeesKey]!.count);
      await _saveToCache('today_v2', _states[_todayKey]!.page, _states[_todayKey]!.items, _states[_todayKey]!.count);
      await _saveToCache('terminees', _states[_termineesKey]!.page, _states[_termineesKey]!.items, _states[_termineesKey]!.count);
      await _db.delete('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId]);
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
