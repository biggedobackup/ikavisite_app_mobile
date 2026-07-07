import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/visit_service.dart';

class SyncService {
  final DatabaseHelper _db = DatabaseHelper();
  final AuthService _authService = AuthService();
  final VisitService _visitService = VisitService();
  bool _isProcessing = false;

  bool get isProcessing => _isProcessing;

  Future<void> enqueue(String action, Map<String, dynamic> payload) async {
    await _db.insert('pending_sync', {
      'action': action,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'status': 0,
    });
    debugPrint('SyncService: enqueued $action');
  }

  Future<void> processQueue({required String? accessToken}) async {
    if (_isProcessing || accessToken == null) return;
    _isProcessing = true;

    try {
      final pending = await _db.query('pending_sync',
          where: 'status = ?', whereArgs: [0], orderBy: 'created_at ASC');

      if (pending.isEmpty) {
        _isProcessing = false;
        return;
      }

      debugPrint('SyncService: processing ${pending.length} pending items');

      for (final item in pending) {
        final id = item['id'] as int;
        final action = item['action'] as String;
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;

        await _db.update('pending_sync',
            {'status': 1},
            where: 'id = ?', whereArgs: [id]);

        try {
          await _processAction(action, payload, accessToken);
          await _db.delete('pending_sync',
              where: 'id = ?', whereArgs: [id]);
          debugPrint('SyncService: completed $action (#$id)');
        } catch (e) {
          debugPrint('SyncService: failed $action (#$id): $e');
          await _db.update('pending_sync',
              {'status': 3},
              where: 'id = ?', whereArgs: [id]);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processAction(
      String action, Map<String, dynamic> payload, String accessToken) async {
    switch (action) {
      case 'update_profile':
        await _authService.updateMe(
          accessToken,
          firstName: payload['first_name'] as String?,
          lastName: payload['last_name'] as String?,
          telephoneMobile: payload['telephone_mobile'] as String?,
          email: payload['email'] as String?,
        );
        break;
      case 'create_visite':
        await _visitService.createVisite(accessToken, payload);
        break;
      case 'update_visite':
        final id = payload['_visite_id'] as int;
        payload.remove('_visite_id');
        await _visitService.updateVisite(accessToken, id, payload);
        break;
      default:
        throw Exception('Unknown action: $action');
    }
  }
}
