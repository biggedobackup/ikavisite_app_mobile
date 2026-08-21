import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';
import 'connectivity_provider.dart';

class SyncProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final ConnectivityProvider _connectivity;
  final String? Function() _getAccessToken;
  final Future<bool> Function()? _onUnauthorized;

  int _pendingCount = 0;
  bool _isSyncing = false;

  SyncProvider(this._connectivity, this._getAccessToken, {Future<bool> Function()? onUnauthorized})
      : _onUnauthorized = onUnauthorized {
    _connectivity.addListener(_onConnectivityChanged);
    refreshPendingCount();
    _trySyncOnStartup();
  }

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  void _trySyncOnStartup() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_connectivity.isConnected && _pendingCount > 0) {
        debugPrint('SyncProvider: startup sync triggered');
        processSync();
      }
    });
  }

  void _onConnectivityChanged() {
    if (_connectivity.isConnected) {
      debugPrint('SyncProvider: connectivity restored, triggering sync');
      processSync();
    }
  }

  Future<void> processSync() async {
    if (_isSyncing) return;
    final token = _getAccessToken();
    if (token == null) return;
    _isSyncing = true;
    notifyListeners();

    await _syncService.processQueue(
      accessToken: token,
      onUnauthorized: _onUnauthorized,
    );

    _isSyncing = false;
    await refreshPendingCount();
  }

  Future<void> refreshPendingCount() async {
    final items = await _db.query('pending_sync',
        where: 'status = ?', whereArgs: [0]);
    if (items.length != _pendingCount) {
      _pendingCount = items.length;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getPendingItems() async {
    return await _db.query('pending_sync',
        where: 'status = ?', whereArgs: [0], orderBy: 'id ASC');
  }

  Future<void> removePendingItem(int id) async {
    await _db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
    await refreshPendingCount();
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
