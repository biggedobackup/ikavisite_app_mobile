import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/dashboard_stats.dart';
import 'http_client.dart';

class DashboardService {
  http.Client get _client => SharedHttpClient.instance;

  Future<DashboardStats> getStats(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.dashboardStats}');

    final response = await _client.get(
      url,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return DashboardStats.fromJson(body);
    } else {
      final msg = body['detail'] as String? ??
          body['message'] as String? ??
          'Erreur de chargement des statistiques';
      throw DashboardException('${response.statusCode}: $msg');
    }
  }
}

class DashboardException implements Exception {
  final String message;
  DashboardException(this.message);

  @override
  String toString() => message;
}
