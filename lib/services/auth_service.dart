import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'http_client.dart';

class AuthService {
  http.Client get _client => SharedHttpClient.instance;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.login}');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body;
    }

    throw AuthException(
        body['detail'] as String? ??
        body['message'] as String? ??
        'Erreur de connexion');
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.refresh}');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'refresh': refreshToken}),
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body;
    }

    throw AuthException(
        body['detail'] as String? ??
        body['message'] as String? ??
        'Erreur de rafraîchissement');
  }

  Future<Map<String, dynamic>> getMe(String accessToken) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.me}');

    final response = await _client.get(
      url,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body;
    }

    throw AuthException(
        body['detail'] as String? ??
        body['message'] as String? ??
        'Erreur de récupération du profil');
  }

  Future<Map<String, dynamic>> updateMe(String accessToken, {
    String? firstName,
    String? lastName,
    String? telephoneMobile,
    String? email,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.me}');
    final pushBody = <String, dynamic>{};
    if (firstName != null) pushBody['first_name'] = firstName;
    if (lastName != null) pushBody['last_name'] = lastName;
    if (telephoneMobile != null) pushBody['telephone_mobile'] = telephoneMobile;
    if (email != null) pushBody['email'] = email;

    final response = await _client.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(pushBody),
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body;
    }

    throw AuthException(
        body['detail'] as String? ??
        body['message'] as String? ??
        'Erreur de mise à jour');
  }

  Future<void> logout(String accessToken) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.logout}');
    final response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(
          body['detail'] as String? ??
          body['message'] as String? ??
          'Erreur de déconnexion');
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
