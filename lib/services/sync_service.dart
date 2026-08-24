import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/visit.dart';
import '../services/auth_service.dart';
import '../services/visit_media.dart';
import '../services/visit_service.dart';

class SyncService {
  final DatabaseHelper _db = DatabaseHelper();
  final AuthService _authService = AuthService();
  final VisitService _visitService = VisitService();
  bool _isProcessing = false;

  /// Prévient l'application qu'une saisie hors ligne vient d'être créée côté
  /// serveur, pour que la copie locale cède la place à la visite serveur.
  Future<void> Function(int pendingId, Visit visit, bool terminee)?
      onVisiteCreee;

  /// Au-delà de ce nombre d'échecs, l'envoi est mis de côté (statut 2) au lieu
  /// d'être réessayé indéfiniment à chaque synchronisation.
  static const int _maxTentatives = 5;

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

  Future<void> processQueue({
    required String? accessToken,
    Future<bool> Function()? onUnauthorized,
  }) async {
    if (_isProcessing || accessToken == null) return;
    _isProcessing = true;

    try {
      await _processQueue(accessToken, onUnauthorized);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processQueue(
      String accessToken, Future<bool> Function()? onUnauthorized) async {
    // Un envoi interrompu — application fermée pendant la requête — resterait
    // bloqué en statut 1 et ne serait jamais repris. On le remet en file.
    await _db.update('pending_sync', {'status': 0},
        where: 'status = ?', whereArgs: [1]);

    final pending = await _db.query('pending_sync',
        where: 'status = ?', whereArgs: [0], orderBy: 'created_at ASC');

    if (pending.isEmpty) return;

    debugPrint('SyncService: processing ${pending.length} pending items');

    for (final item in pending) {
      final id = item['id'] as int;
      final action = item['action'] as String;
      final tentatives = (item['tentatives'] as int?) ?? 0;
      final payload =
          jsonDecode(item['payload'] as String) as Map<String, dynamic>;

      await _db.update('pending_sync', {'status': 1},
          where: 'id = ?', whereArgs: [id]);

      try {
        await _processAction(id, action, payload, accessToken);
        await _db.delete('pending_sync',
            where: 'id = ?', whereArgs: [id]);
        debugPrint('SyncService: completed $action (#$id)');
      } catch (e) {
        final msg = e.toString();
        debugPrint('SyncService: failed $action (#$id): $e');

        if ((msg.contains('401') || msg.contains('Unauthorized')) &&
            onUnauthorized != null) {
          // L'échec vient de la session, pas de l'enregistrement : il ne
          // compte pas comme une tentative.
          await onUnauthorized();
          await _db.update('pending_sync', {'status': 0},
              where: 'id = ?', whereArgs: [id]);
          continue;
        }

        final essais = tentatives + 1;
        if (essais >= _maxTentatives) {
          await _db.update('pending_sync', {'status': 2, 'tentatives': essais},
              where: 'id = ?', whereArgs: [id]);
          debugPrint('SyncService: $action (#$id) mis de côté après $essais tentatives');
        } else {
          await _db.update('pending_sync', {'status': 0, 'tentatives': essais},
              where: 'id = ?', whereArgs: [id]);
        }
      }
    }
  }

  Future<void> _processAction(int pendingId,
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
        final terminerApres = payload.remove('_terminer_apres_creation') == true;
        final terminationBody = payload.remove('_termination_body') as Map<String, dynamic>?;
        // Les images ne sont encodées qu'ici, juste avant de partir.
        final created = await _visitService.createVisite(
            accessToken, await VisitMedia.toApiBody(payload));
        if (terminerApres) {
          try {
            await _visitService.terminerVisite(accessToken, created.id, body: terminationBody);
          } catch (e) {
            debugPrint('SyncService: clôture après création échouée, rejetée : $e');
            await enqueue('terminer_visite', {
              '_visite_id': created.id,
              ...?terminationBody,
            });
          }
        }
        await VisitMedia.discard(payload);
        try {
          await onVisiteCreee?.call(pendingId, created, terminerApres);
        } catch (e) {
          debugPrint('SyncService: remplacement de la copie locale échoué : $e');
        }
        break;
      case 'update_visite':
        final id = payload['_visite_id'] as int;
        payload.removeWhere((k, _) => k.startsWith('_'));
        await _visitService.updateVisite(accessToken, id, payload);
        break;
      case 'terminer_visite':
        final id = payload['_visite_id'] as int;
        payload.removeWhere((k, _) => k.startsWith('_'));
        await _visitService.terminerVisite(accessToken, id, body: payload);
        break;
      default:
        throw Exception('Unknown action: $action');
    }
  }
}
