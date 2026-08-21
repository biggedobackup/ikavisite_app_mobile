import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/dashboard_stats.dart';
import '../services/dashboard_service.dart';
import '../services/cancel_token.dart';
import 'connectivity_provider.dart';

class DashboardProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final DashboardService _dashboardService = DashboardService();
  final ConnectivityProvider _connectivity;
  CancelToken? _cancelToken;

  DashboardStats? _stats;
  bool _isLoading = false;
  String? _error;

  DashboardProvider(this._connectivity) {
    _connectivity.addListener(() => notifyListeners());
  }

  DashboardStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _connectivity.isConnected;

  void cancelPending() {
    _cancelToken?.cancel();
  }

  void clearStats() {
    _stats = null;
    _isLoading = true;
    _error = null;
  }

  Future<void> loadStats(String token, {Future<bool> Function()? onUnauthorized}) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    // 1. Afficher d'abord les données en cache SQLite
    final hasExistingData = _stats != null;
    if (!hasExistingData) {
      final cached = await _db.getFirst('dashboard_cache');
      if (cached != null) {
        try {
          final json = jsonDecode(cached['stats_json'] as String) as Map<String, dynamic>;
          _stats = DashboardStats.fromJson(json);
        } catch (_) {}
      }
      if (_stats == null) _isLoading = true;
      _error = null;
      notifyListeners();
    }

    // 2. Rafraîchir silencieusement depuis le réseau si connecté
    if (_connectivity.isConnected) {
      try {
        _cancelToken!.throwIfCancelled();
        final fresh = await _dashboardService.getStats(token);
        _stats = fresh;
        await _saveStatsToCache(fresh);
        _error = null;
      } catch (e) {
        debugPrint('Dashboard API error: $e');
        final msg = e.toString();

        if ((msg.contains('401') || msg.contains('Unauthorized')) && onUnauthorized != null) {
          final refreshed = await onUnauthorized();
          if (refreshed) {
            await loadStats(token, onUnauthorized: null);
            _isLoading = false;
            notifyListeners();
            return;
          }
        }

        if (_stats == null) _error = msg;
      }
    } else {
      if (_stats == null) {
        _error = 'Aucune donnée en cache. Connectez-vous à Internet pour synchroniser.';
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveStatsToCache(DashboardStats stats) async {
    final existing = await _db.getFirst('dashboard_cache');
    final data = {
      'stats_json': jsonEncode(stats.toJson()),
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (existing != null) {
      await _db.update('dashboard_cache', data);
    } else {
      await _db.insert('dashboard_cache', data);
    }
  }
}
