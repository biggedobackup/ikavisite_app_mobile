import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';
import 'connectivity_provider.dart';

class SyncProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final ConnectivityProvider _connectivity;
  final String? Function() _getAccessToken;

  int _pendingCount = 0;
  bool _isSyncing = false;

  SyncProvider(this._connectivity, this._getAccessToken) {
    _connectivity.addListener(_onConnectivityChanged);
    refreshPendingCount();
  }

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  void _onConnectivityChanged() {
    if (_connectivity.isConnected) {
      debugPrint('SyncProvider: connectivity restored, triggering sync');
      processSync();
    }
  }

  Future<void> processSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    await _syncService.processQueue(accessToken: _getAccessToken());

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

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
