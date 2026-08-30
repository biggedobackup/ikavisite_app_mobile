import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/visit.dart';
import '../services/visit_media.dart';
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

  SyncProvider(this._connectivity, this._getAccessToken,
      {Future<bool> Function()? onUnauthorized,
      Future<void> Function(int pendingId, Visit visit, bool terminee,
              Map<String, dynamic> payload)?
          onVisiteCreee})
      : _onUnauthorized = onUnauthorized {
    _syncService.onVisiteCreee = onVisiteCreee;
    _connectivity.addListener(_onConnectivityChanged);
    refreshPendingCount();
    _trySyncOnStartup();
  }

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  void _trySyncOnStartup() {
    Future.delayed(const Duration(milliseconds: 500), () async {
      // Le compteur se charge en asynchrone : sans cette attente, il valait
      // encore zéro et la synchronisation de démarrage ne partait jamais.
      await refreshPendingCount();
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
    // COUNT(*) plutôt que de charger la file entière : avec des milliers de
    // saisies contenant des photos, la lire pour en compter les lignes
    // représentait des centaines de méga-octets.
    final db = await _db.database;
    // Les envois mis de côté (statut 2) restent comptés : sinon ils
    // deviendraient invisibles et l'agent ne pourrait plus les traiter.
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM pending_sync WHERE status IN (0, 2)');
    final count = (rows.first['n'] as int?) ?? 0;
    if (count != _pendingCount) {
      _pendingCount = count;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getPendingItems() async {
    return await _db.query('pending_sync',
        where: 'status IN (0, 2)', orderBy: 'id ASC');
  }

  Future<void> removePendingItem(int id) async {
    // Les images d'une saisie abandonnée n'ont plus de raison d'occuper le
    // disque : on les supprime avant de perdre la référence.
    final rows = await _db.query('pending_sync',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      try {
        await VisitMedia.discard(
            jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('SyncProvider: images de #$id non supprimées : $e');
      }
    }
    await _db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
    await refreshPendingCount();
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
