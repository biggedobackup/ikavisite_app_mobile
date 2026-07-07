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
    if (_connectivity.isConnected) {
      try {
        await _visitService.updateVisite(token, visiteId, body);
        await _db.delete('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId]);
        return true;
      } catch (e) {
        final msg = e.toString();
        if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
          final refreshed = await onUnauthorized();
          if (refreshed) return await updateVisite(token, visiteId, body, onUnauthorized: null);
        }
        _error = msg;
        notifyListeners();
        return false;
      }
    }
    body['_visite_id'] = visiteId;
    await _db.insert('pending_sync', {'action': 'update_visite', 'payload': jsonEncode(body), 'created_at': DateTime.now().toIso8601String(), 'status': 0});
    await _db.delete('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId]);
    return true;
  }

  Future<void> createVisite(String token, Map<String, dynamic> body, {Future<bool> Function()? onUnauthorized}) async {
    final pendingId = await _db.insert('pending_sync', {
      'action': 'create_visite',
      'payload': jsonEncode(body),
      'created_at': DateTime.now().toIso8601String(),
      'status': 0,
    });

    if (_connectivity.isConnected) {
      _tryCreateOnline(token, body, pendingId, onUnauthorized);
    }
  }

  Future<void> _tryCreateOnline(String token, Map<String, dynamic> body, int pendingId,
      Future<bool> Function()? onUnauthorized) async {
    try {
      final visit = await _visitService.createVisite(token, body);
      await _addCreatedVisit(visit);
      await _db.delete('pending_sync', where: 'id = ?', whereArgs: [pendingId]);
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) {
          _tryCreateOnline(token, body, pendingId, null);
          return;
        }
      }
      debugPrint('[VisitProvider] Création en arrière-plan échouée, en file d\'attente : $e');
    }
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

  // ── Sync ──

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    return await _db.query('pending_sync', where: 'status = ?', whereArgs: [0], orderBy: 'id ASC');
  }

  Future<void> markSynced(int pendingId) async {
    await _db.update('pending_sync', {'status': 1}, where: 'id = ?', whereArgs: [pendingId]);
  }

  Future<bool> terminerVisite(String token, int visiteId, {Map<String, dynamic>? body, Future<bool> Function()? onUnauthorized}) async {
    try {
      await _visitService.terminerVisite(token, visiteId, body: body);
      final visit = _findInLists(visiteId);

      for (final key in [_enCoursKey, _excedeesKey, _todayKey]) {
        final state = _states[key]!;
        state.items.removeWhere((v) => v.id == visiteId);
        state.count = state.count.clamp(0, 999999);
      }

      if (visit != null) {
        final terminees = _states[_termineesKey]!;
        terminees.items.insert(0, visit.copyWith(statut: 'TERMINEE'));
        terminees.count++;
        await _saveToCache('terminees', terminees.page, terminees.items, terminees.count);
      }

      await _db.delete('visit_detail_cache', where: 'id = ?', whereArgs: [visiteId]);
      await _saveToCache('en_cours', _states[_enCoursKey]!.page, _states[_enCoursKey]!.items, _states[_enCoursKey]!.count);
      await _saveToCache('excedees', _states[_excedeesKey]!.page, _states[_excedeesKey]!.items, _states[_excedeesKey]!.count);
      await _saveToCache('today_v2', _states[_todayKey]!.page, _states[_todayKey]!.items, _states[_todayKey]!.count);
      notifyListeners();
      return true;
    } catch (e) {
      final msg = e.toString();
      if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
        final refreshed = await onUnauthorized();
        if (refreshed) return await terminerVisite(token, visiteId, body: body, onUnauthorized: null);
      }
      _error = msg;
      notifyListeners();
      return false;
    }
  }
}
