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

  Future<void> checkSession() async {
    _isLoading = true;
    notifyListeners();

    final result = await _db.getFirst('users', where: 'is_connected = ?', whereArgs: [1]);
    if (result != null) {
      _user = User.fromMap(result);
      if (_connectivity.isConnected && _user!.accessToken != null) {
        try {
          final userData = await _authService.getMe(_user!.accessToken!);
          _user = User.fromJson(
            userData,
            accessToken: _user!.accessToken,
            refreshToken: _user!.refreshToken,
          );
          await _saveUser(_user!);
        } catch (_) {
          if (_user!.refreshToken != null) {
            await _tryRefreshToken();
          }
        }
      }
    }

    _isLoading = false;
    notifyListeners();
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

  Future<void> logout() async {
    if (_connectivity.isConnected && _user?.accessToken != null) {
      try {
        await _authService.logout(_user!.accessToken!);
      } catch (_) {}
    }

    await _db.delete('users', where: 'is_connected = ?', whereArgs: [1]);
    await _db.clearTable('dashboard_cache');
    await _db.clearTable('visits_cache');
    _user = null;
    notifyListeners();
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

    if (_connectivity.isConnected) {
      try {
        final response = await _authService.updateMe(
          _user!.accessToken!,
          firstName: firstName,
          lastName: lastName,
          telephoneMobile: telephoneMobile,
          email: email,
        );
        final updated = User.fromJson(
          response['user'] as Map<String, dynamic>? ?? response,
          accessToken: _user!.accessToken,
          refreshToken: _user!.refreshToken,
        );
        _user = _user!.copyWith(
          firstName: updated.firstName,
          lastName: updated.lastName,
          telephoneMobile: updated.telephoneMobile,
          email: updated.email,
        );
        await _saveUser(_user!);
        notifyListeners();
      } catch (e) {
        debugPrint('updateProfile API failed, queuing sync: $e');
        await _syncService.enqueue('update_profile', {
          'first_name': firstName,
          'last_name': lastName,
          'telephone_mobile': telephoneMobile,
          'email': email,
        });
      }
    } else {
      await _syncService.enqueue('update_profile', {
        'first_name': firstName,
        'last_name': lastName,
        'telephone_mobile': telephoneMobile,
        'email': email,
      });
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
