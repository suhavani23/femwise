import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AccountUser {
  final String uid;
  final String email;
  const AccountUser({required this.uid, required this.email});
  factory AccountUser.fromJson(Map<String, dynamic> json) =>
      AccountUser(uid: json['uid'] as String, email: json['email'] as String);
}

class AccountException implements Exception {
  final String message;
  const AccountException(this.message);
  @override
  String toString() => message;
}

/// All database credentials and password verification stay on the server.
class AccountService {
  AccountService._();
  static final instance = AccountService._();
  static const baseUrl = String.fromEnvironment('ACCOUNT_API_URL',
      defaultValue: 'http://10.0.2.2:8002');
  static const _storage = FlutterSecureStorage();
  final _changes = StreamController<AccountUser?>.broadcast();
  AccountUser? currentUser;
  String? _token;

  Stream<AccountUser?> authStateChanges() async* {
    yield currentUser;
    yield* _changes.stream;
  }

  Future<void> initialize() async {
    _token = await _storage.read(key: 'account_token');
    if (_token == null) return;
    // Network failures remain visible so startup can be retried without erasing
    // a valid session. A rejected/expired session is cleared in _request.
    try {
      currentUser = AccountUser.fromJson(await getProfile());
    } on AccountException {
      if (_token != null) rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body, bool authenticated = true}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (authenticated && _token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    if (body != null) request.body = jsonEncode(body);
    final client = http.Client();
    late http.Response response;
    try {
      response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }
    if (response.statusCode == 401 && authenticated) {
      await _clearSession();
    }
    final dynamic data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] : null;
      throw AccountException(detail is String ? detail : 'Request failed (${response.statusCode}). Check your inputs.');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<AccountUser> signIn({required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<AccountUser> register({required String name, required String email,
      required String password}) => _authenticate('/auth/register',
      {'name': name, 'email': email, 'password': password});

  Future<AccountUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _request('POST', path, body: body, authenticated: false);
    _token = data['access_token'] as String;
    await _storage.write(key: 'account_token', value: _token);
    currentUser = AccountUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    _changes.add(currentUser);
    return currentUser!;
  }

  Future<void> _clearSession() async {
    _token = null;
    currentUser = null;
    await _storage.delete(key: 'account_token');
    _changes.add(null);
  }

  Future<void> signOut() async {
    // A failed revoke stays visible and can be retried. Expired sessions are
    // already cleared by _request, and may always leave the login screen.
    try {
      if (_token != null) await _request('POST', '/auth/logout');
    } on AccountException {
      if (_token != null) rethrow;
    }
    await _clearSession();
  }

  Future<Map<String, dynamic>> getProfile() => _request('GET', '/me');
  Future<void> updateProfile(Map<String, dynamic> data) async {
    await _request('PATCH', '/me', body: data);
  }
  Future<Map<String, dynamic>?> getDailyLog(String day) async {
    // The API uses 404 specifically for an absent daily log.
    try {
      return await _request('GET', '/me/daily-logs/$day');
    } on AccountException catch (e) {
      if (e.message == 'No log for this date.') return null;
      rethrow;
    }
  }
  Future<void> saveDailyLog(String day, Map<String, dynamic> log,
      Map<String, dynamic> profile) async {
    await _request('PUT', '/me/daily-logs/$day', body: {'log': log, 'profile': profile});
  }
}
