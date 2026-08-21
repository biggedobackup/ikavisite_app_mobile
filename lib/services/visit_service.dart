import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/visit.dart';
import 'http_client.dart';

class VisitService {
  http.Client get _client => SharedHttpClient.instance;

  Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<VisitListResponse> getVisites(String token, {int page = 1, bool aujourdhui = false}) async {
    final queryParams = {'page': '$page'};
    if (aujourdhui) queryParams['aujourdhui'] = 'true';
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visites}?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}');

    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitListResponse.fromJson(body);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  Future<VisitListResponse> getVisitesEnCours(String token, {int page = 1}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visitesEnCours}?page=$page');

    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitListResponse.fromJson(body);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  Future<VisitListResponse> getVisitesTerminees(String token, {int page = 1, bool aujourdhui = true}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visitesTerminees}?page=$page${aujourdhui ? '&aujourdhui=true' : ''}');

    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitListResponse.fromJson(body);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  Future<VisitListResponse> getVisitesExcedees(String token, {int page = 1}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visitesExcedees}?page=$page');

    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return VisitListResponse.fromJson(body);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  Future<Visit> getVisite(String token, int visiteId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visiteById(visiteId)}');

    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Visit.fromJson(body);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  Future<void> terminerVisite(String token, int visiteId, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visiteTerminer(visiteId)}');

    final response = await _client.post(
      url,
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: body != null ? jsonEncode(body) : null,
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode != 200) {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  String _parseErrorMessage(String responseBody) {
    try {
      final body = jsonDecode(responseBody);
      if (body is Map) {
        if (body['detail'] is String) return body['detail'] as String;
        if (body['message'] is String) return body['message'] as String;
      }
    } catch (_) {}
    return 'Erreur de chargement des visites';
  }

  // ── Dropdowns ──

  List<Map<String, dynamic>> _parseList(String responseBody) {
    final body = jsonDecode(responseBody);
    if (body is List) return body.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (body is Map) {
      final items = body['items'] ?? body['results'] ?? body['data'] ?? [];
      if (items is List) return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getTypesVisite(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.typesVisite}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement types de visite');
  }

  Future<List<Map<String, dynamic>>> getPortesEntree(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.portesEntree}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement portes d\'entrée');
  }

  Future<List<Map<String, dynamic>>> getPersonnel(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.personnel}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement personnel');
  }

  Future<List<Map<String, dynamic>>> getDepartements(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.departements}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement départements');
  }

  Future<Map<String, dynamic>> getReferences(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.references}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'nationalites': (body['nationalites'] as List? ?? []).map((e) => e.toString()).toList(),
        'pays': (body['pays'] as List? ?? []).map((e) => e.toString()).toList(),
        'types_piece': (body['types_piece'] as List? ?? []).map((e) => e.toString()).toList(),
        'duree_moyenne_visites': body['duree_moyenne_visites'] ?? 60,
      };
    }
    throw VisitException('Erreur chargement references');
  }

  Future<List<Map<String, dynamic>>> getCreneaux(String token) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.creneaux}');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement creneaux');
  }

  Future<Map<String, dynamic>> checkMode(String token, {required String date, required String heure}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.checkMode}?date=$date&heure=$heure');
    final response = await _client.get(url, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutReferences));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw VisitException('Erreur vérification mode visite');
  }

  Future<List<Map<String, dynamic>>> searchVisiteurs(String token, {String? query}) async {
    final queryParams = <String, String>{};
    if (query != null && query.isNotEmpty) queryParams['search'] = query;
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visiteurs}').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await _client.get(uri, headers: _headers(token)).timeout(Duration(seconds: ApiConfig.timeoutDefault));
    if (response.statusCode == 200) return _parseList(response.body);
    throw VisitException('Erreur chargement visiteurs');
  }

  // ── Update Visite ──

  Future<Visit> updateVisite(String token, int visiteId, Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visiteById(visiteId)}');
    final response = await _client.put(
      url,
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(Duration(seconds: ApiConfig.timeoutDefault));

    if (response.statusCode == 200) {
      return Visit.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }

  // ── Create Visite ──

  Future<Visit> createVisite(String token, Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.visites}');

    final response = await _client.post(
      url,
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(Duration(seconds: ApiConfig.timeoutUpload));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      return Visit.fromJson(responseBody);
    } else {
      final msg = _parseErrorMessage(response.body);
      throw VisitException('${response.statusCode}: $msg');
    }
  }
}

class VisitException implements Exception {
  final String message;
  VisitException(this.message);

  @override
  String toString() => message;
}
