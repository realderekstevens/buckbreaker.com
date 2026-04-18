import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Config ─────────────────────────────────────────────────────────────────────
// Change baseUrl for production: 'https://api.yourstockforecast.com'
// or for Patrician game: 'http://localhost:3000'
class ApiConfig {
  static const String baseUrl   = 'http://localhost:3000';
  static const Duration timeout = Duration(seconds: 15);
}

// ── Auth state ─────────────────────────────────────────────────────────────────
class AuthService extends ChangeNotifier {
  static const _tokenKey = 'jwt_token';
  static const _emailKey = 'user_email';
  static const _roleKey  = 'user_role';

  String? _token;
  String? _email;
  String? _role;

  String? get token  => _token;
  String? get email  => _email;
  String? get role   => _role;
  bool get isLoggedIn => _token != null && !_isExpired(_token!);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _email = prefs.getString(_emailKey);
    _role  = prefs.getString(_roleKey);
    if (_token != null && _isExpired(_token!)) await logout();
    notifyListeners();
  }

  bool _isExpired(String token) {
    try {
      final parts   = token.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'] as int?;
      if (exp == null) return false;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp;
    } catch (_) { return true; }
  }

  Future<void> login(String email, String password) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/rpc/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    ).timeout(ApiConfig.timeout);

    if (resp.statusCode != 200) {
      final body = json.decode(resp.body);
      throw Exception(body['message'] ?? 'Login failed');
    }

    final data   = json.decode(resp.body) as Map;
    final token  = data['token'] as String?;
    if (token == null) throw Exception('No token returned from server');

    // Decode role from JWT payload
    final parts   = token.split('.');
    final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));

    _token = token;
    _email = email;
    _role  = payload['role'] as String? ?? 'app_user';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_emailKey, _email!);
    await prefs.setString(_roleKey,  _role!);
    notifyListeners();
  }

  Future<void> register(String email, String password, {String? displayName}) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/rpc/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email, 'password': password,
        if (displayName != null) 'display_name': displayName,
      }),
    ).timeout(ApiConfig.timeout);
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body);
      throw Exception(body['message'] ?? 'Registration failed');
    }
  }

  Future<void> logout() async {
    _token = _email = _role = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
    notifyListeners();
  }
}

// ── Base API client ────────────────────────────────────────────────────────────
class ApiClient {
  final AuthService _auth;
  ApiClient(this._auth);

  Map<String, String> get _headers => {
    'Accept':       'application/json',
    'Content-Type': 'application/json',
    'Prefer':       'count=exact',
    if (_auth.isLoggedIn) 'Authorization': 'Bearer ${_auth.token}',
  };

  Uri _uri(String path, [Map<String, String>? params]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(
        queryParameters: params,
      );

  Future<ApiResponse> get(String path, {Map<String, String>? params}) async {
    try {
      final resp = await http.get(_uri(path, params), headers: _headers)
          .timeout(ApiConfig.timeout);
      return _handle(resp);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<ApiResponse> post(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http.post(
        _uri(path), headers: _headers, body: json.encode(body),
      ).timeout(ApiConfig.timeout);
      return _handle(resp);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<ApiResponse> patch(String path, Map<String, dynamic> body,
      {Map<String, String>? params}) async {
    try {
      final resp = await http.patch(
        _uri(path, params), headers: _headers, body: json.encode(body),
      ).timeout(ApiConfig.timeout);
      return _handle(resp);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  ApiResponse _handle(http.Response resp) {
    if (resp.statusCode == 401) throw ApiException('Unauthorised — please log in');
    if (resp.statusCode == 403) throw ApiException('Forbidden');
    if (resp.statusCode >= 400) {
      Map<String, dynamic> body = {};
      try { body = json.decode(resp.body); } catch (_) {}
      throw ApiException(body['message'] ?? 'HTTP ${resp.statusCode}');
    }
    final totalStr = resp.headers['content-range']?.split('/').last;
    final total    = int.tryParse(totalStr ?? '');
    dynamic data;
    try {
      data = resp.body.isEmpty ? null : json.decode(resp.body);
    } catch (_) {
      data = resp.body;
    }
    return ApiResponse(data: data, total: total);
  }
}

class ApiResponse {
  final dynamic data;
  final int? total;
  const ApiResponse({this.data, this.total});
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override String toString() => message;
}

// ── Stock service ──────────────────────────────────────────────────────────────
class StockService {
  final ApiClient _api;
  StockService(this._api);

  Future<List<Map<String, dynamic>>> getLatestQuotes({
    int limit = 50, int offset = 0,
    String order = 'symbol',
    Map<String, String>? filters,
  }) async {
    final params = {
      'limit': '$limit', 'offset': '$offset', 'order': order,
      ...?filters,
    };
    final r = await _api.get('/latest_quotes', params: params);
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<Map<String, dynamic>?> getStock(String symbol) async {
    final r = await _api.get('/latest_quotes', params: {
      'symbol': 'eq.${symbol.toUpperCase()}', 'limit': '1',
    });
    final list = r.data as List?;
    return list != null && list.isNotEmpty
        ? Map<String, dynamic>.from(list.first as Map)
        : null;
  }

  Future<List<Map<String, dynamic>>> getHistory(String symbol,
      {int limit = 30}) async {
    final r = await _api.get('/stock_quote', params: {
      'symbol': 'eq.${symbol.toUpperCase()}',
      'order': 'time_recorded.desc',
      'limit': '$limit',
    });
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> getGainers({int limit = 25}) =>
      getLatestQuotes(
        limit: limit,
        order: 'performance_today.desc',
        filters: {'performance_today': 'not.is.null'},
      );

  Future<List<Map<String, dynamic>>> getLosers({int limit = 25}) =>
      getLatestQuotes(
        limit: limit,
        order: 'performance_today.asc',
        filters: {'performance_today': 'not.is.null'},
      );

  Future<List<Map<String, dynamic>>> getMostActive({int limit = 25}) =>
      getLatestQuotes(
        limit: limit,
        order: 'volume.desc',
        filters: {'volume': 'not.is.null'},
      );

  Future<Map<String, dynamic>?> getMarketSummary() async {
    final r = await _api.get('/rpc/market_summary');
    return r.data as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>>> getSectorPerformance() async {
    final r = await _api.get('/rpc/sector_performance');
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }
}

// ── Patrician game service ─────────────────────────────────────────────────────
class GameService {
  final ApiClient _api;
  GameService(this._api);

  Future<Map<String, dynamic>?> getPlayer() async {
    final r = await _api.get('/p3_player', params: {'limit': '1'});
    final list = r.data as List?;
    return list != null && list.isNotEmpty
        ? Map<String, dynamic>.from(list.first as Map)
        : null;
  }

  Future<List<Map<String, dynamic>>> getFleet() async {
    final r = await _api.get('/p3_fleet_view');
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> getCities() async {
    final r = await _api.get('/p3_cities', params: {'order': 'name'});
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> getMarket(String city) async {
    final r = await _api.get('/p3_market_view', params: {
      'city': 'eq.$city', 'order': 'good',
    });
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> getArbitrage() async {
    final r = await _api.get('/p3_arbitrage_view', params: {
      'order': 'profit_per_unit.desc', 'limit': '20',
    });
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> getTradeLog({int limit = 40}) async {
    final r = await _api.get('/p3_trade_log', params: {
      'order': 'log_id.desc', 'limit': '$limit',
    });
    return List<Map<String, dynamic>>.from(r.data as List? ?? []);
  }

  Future<void> advanceDay() async {
    // Calls the advance function via RPC
    await _api.post('/rpc/p3_advance_day_api', {});
  }

  Future<void> buyGoods({
    required int shipId,
    required String good,
    required int quantity,
    required String city,
  }) async {
    await _api.post('/rpc/p3_do_buy_api', {
      'p_ship_id': shipId,
      'p_good':    good,
      'p_qty':     quantity,
      'p_city':    city,
    });
  }

  Future<void> sellGoods({
    required int shipId,
    required String good,
    required int quantity,
    required String city,
  }) async {
    await _api.post('/rpc/p3_do_sell_api', {
      'p_ship_id': shipId,
      'p_good':    good,
      'p_qty':     quantity,
      'p_city':    city,
    });
  }

  Future<void> sailShip({
    required int shipId,
    required String destination,
  }) async {
    await _api.patch(
      '/p3_ships',
      {'status': 'sailing', 'destination': destination},
      params: {'ship_id': 'eq.$shipId'},
    );
  }
}
