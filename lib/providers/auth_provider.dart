import 'dart:async';

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import 'connectivity_provider.dart';

class AuthProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final AuthService _authService = AuthService();
  final SyncService _syncService = SyncService();
  final ConnectivityProvider _connectivity;

  User? _user;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._connectivity);

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null && _user!.isConnected;
  String? get accessToken => _user?.accessToken;
  String? get refreshToken => _user?.refreshToken;

  /// Restaure la session depuis SQLite uniquement : aucun appel reseau.
  /// C'est ce qui decide de la route de demarrage, donc ca doit rester
  /// quasi instantane.
  Future<void> restoreLocalSession() async {
    final result = await _db.getFirst('users', where: 'is_connected = ?', whereArgs: [1]);
    if (result == null) return;
    _user = User.fromMap(result);
    notifyListeners();
  }

  /// Rafraichit le profil depuis l'API sans bloquer l'interface. En cas
  /// d'echec la session locale reste utilisable (mode hors ligne) et un
  /// eventuel 401 sera traite par les ecrans via [refreshAccessToken].
  Future<void> refreshSessionInBackground() async {
    final token = _user?.accessToken;
    if (token == null || !_connectivity.isConnected) return;

    try {
      final userData = await _authService.getMe(token);
      final current = _user;
      // L'utilisateur a pu se deconnecter pendant l'appel reseau.
      if (current == null) return;
      _user = User.fromJson(
        userData,
        accessToken: current.accessToken,
        refreshToken: current.refreshToken,
      );
      await _saveUser(_user!);
      notifyListeners();
    } catch (_) {
      if (_user?.refreshToken != null && await _tryRefreshToken()) {
        notifyListeners();
      }
    }
  }

  Future<void> checkSession() async {
    await restoreLocalSession();
    unawaited(refreshSessionInBackground());
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.login(username, password);
      final userData = response['user'] as Map<String, dynamic>? ?? {};
      _user = User.fromJson(
        userData,
        accessToken: response['access'] as String?,
        refreshToken: response['refresh'] as String?,
      );

      await _saveUser(_user!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _tryRefreshToken() async {
    if (_user?.refreshToken == null) return false;

    try {
      final response = await _authService.refresh(_user!.refreshToken!);
      final newAccess = response['access'] as String?;
      if (newAccess != null) {
        _user = _user!.copyWith(accessToken: newAccess);
        await _saveUser(_user!);
        return true;
      }
    } catch (_) {
    }

    return false;
  }

  Future<bool> refreshAccessToken() async {
    return _tryRefreshToken();
  }

  /// Deconnexion immediate. La notification du serveur part en tache de fond :
  /// avec un reseau degrade elle peut prendre jusqu'a 15 s (timeout), et
  /// l'utilisateur restait bloque sur l'ecran precedent pendant tout ce temps.
  /// La session locale, elle, est purgee tout de suite.
  Future<void> logout() async {
    final token = _user?.accessToken;
    if (_connectivity.isConnected && token != null) {
      unawaited(_authService.logout(token).catchError((Object _) {}));
    }

    _user = null;
    notifyListeners();

    await _db.delete('users', where: 'is_connected = ?', whereArgs: [1]);
    // Toutes les donnees en cache appartiennent au compte qui se deconnecte :
    // elles ne doivent pas rester visibles pour le compte suivant.
    // `pending_sync` est volontairement conserve — ce sont des saisies de
    // l'utilisateur pas encore envoyees, les effacer serait une perte de
    // donnees. Elles repartiront a la prochaine synchronisation.
    for (final table in const [
      'dashboard_cache',
      'visits',
      'visit_listes',
      'visits_meta',
      'visiteurs',
      'dropdown_cache',
    ]) {
      await _db.clearTable(table);
    }
  }

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? telephoneMobile,
    String? email,
  }) async {
    if (_user == null || _user!.accessToken == null) return;

    _user = _user!.copyWith(
      firstName: firstName,
      lastName: lastName,
      telephoneMobile: telephoneMobile,
      email: email,
    );
    await _saveUser(_user!);
    _error = null;
    notifyListeners();

    // La modification est deja enregistree localement : on rend la main tout
    // de suite et on pousse vers le serveur en tache de fond. En cas d'echec
    // (ou hors ligne) elle part dans pending_sync, donc rien n'est perdu.
    unawaited(_pushProfileUpdate(
      firstName: firstName,
      lastName: lastName,
      telephoneMobile: telephoneMobile,
      email: email,
    ));
  }

  Future<void> _pushProfileUpdate({
    String? firstName,
    String? lastName,
    String? telephoneMobile,
    String? email,
  }) async {
    Future<void> queue() => _syncService.enqueue('update_profile', {
          'first_name': firstName,
          'last_name': lastName,
          'telephone_mobile': telephoneMobile,
          'email': email,
        });

    final token = _user?.accessToken;
    if (!_connectivity.isConnected || token == null) {
      await queue();
      return;
    }

    try {
      final response = await _authService.updateMe(
        token,
        firstName: firstName,
        lastName: lastName,
        telephoneMobile: telephoneMobile,
        email: email,
      );
      final current = _user;
      // L'utilisateur a pu se deconnecter pendant l'appel reseau.
      if (current == null) return;
      final updated = User.fromJson(
        response['user'] as Map<String, dynamic>? ?? response,
        accessToken: current.accessToken,
        refreshToken: current.refreshToken,
      );
      _user = current.copyWith(
        firstName: updated.firstName,
        lastName: updated.lastName,
        telephoneMobile: updated.telephoneMobile,
        email: updated.email,
      );
      await _saveUser(_user!);
      notifyListeners();
    } catch (e) {
      debugPrint('updateProfile API failed, queuing sync: $e');
      await queue();
    }
  }

  Future<void> _saveUser(User user) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('users', where: 'is_connected = ?', whereArgs: [1]);
      await txn.insert('users', user.toMap());
    });
  }
}
