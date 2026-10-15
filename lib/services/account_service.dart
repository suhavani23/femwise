import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'demo_tracking_data.dart';

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
  String get baseUrl => ApiConfig.accounts;
  static const _storage = FlutterSecureStorage();
  final _changes = StreamController<AccountUser?>.broadcast();
  AccountUser? currentUser;
  String? _token;
  static const _guestUser =
      AccountUser(uid: 'local-guest', email: 'guest@local.invalid');
  static const _guestDataKey = 'guest_tracking_data_v1';
  static const _demoDataKey = 'demo_tracking_data_v1';
  bool _demoMode = false;
  bool get demoMode => _demoMode;
  String get _activeDataKey => _demoMode ? _demoDataKey : _guestDataKey;
  Future<void>? _pendingWrite;

  Future<void> _writeGuestData(Future<void> Function() operation) {
    final previous = _pendingWrite;
    final completion = Completer<void>();
    _pendingWrite = completion.future;
    Future<void> run() async {
      try {
        if (previous != null) await previous;
        await operation();
      } finally {
        if (identical(_pendingWrite, completion.future)) _pendingWrite = null;
        // Release the next save even if this operation failed.
        completion.complete();
      }
    }

    return run();
  }

  Future<Map<String, dynamic>> _guestData() async {
    final stored = await _storage.read(key: _activeDataKey);
    return stored == null
        ? <String, dynamic>{
            'profile': {
              'name': 'Guest',
              'onboardingComplete': false,
              'currentCycleStatus': 'NOT_PERIOD'
            },
            'logs': <String, dynamic>{},
          }
        : Map<String, dynamic>.from(jsonDecode(stored) as Map);
  }

  Future<Map<String, String>> foodAuthorizationHeaders(
      {bool refresh = false}) async {
    // Food services keep their own data access protected without a login screen.
    if (refresh) _token = null;
    if (_token == null) {
      var key = await _storage.read(key: 'guest_service_key');
      if (key == null) {
        final random = Random.secure();
        key = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
        await _storage.write(key: 'guest_service_key', value: key);
      }
      final data = await _request('POST', '/auth/guest',
          body: {'key': key}, authenticated: false);
      _token = data['access_token'] as String;
    }
    return {'Authorization': 'Bearer $_token'};
  }

  Map<String, String> get authorizationHeaders {
    if (_token == null) {
      throw const AccountException('Please sign in before analyzing food.');
    }
    return {'Authorization': 'Bearer $_token'};
  }

  Stream<AccountUser?> authStateChanges() async* {
    yield currentUser;
    yield* _changes.stream;
  }

  Future<void> initialize() async {
    await ApiConfig.initialize();
    final selection = await _storage.read(key: 'demo_tracking_enabled');
    final realData = await _storage.read(key: _guestDataKey);
    // New installations show requested mock history; existing records stay real.
    await setDemoMode(
        selection == 'true' || (selection == null && realData == null));
    await _guestData();
    currentUser = _guestUser;
    _changes.add(currentUser);
  }

  Future<void> setDemoMode(bool enabled) => _writeGuestData(() async {
        if (enabled && await _storage.read(key: _demoDataKey) == null) {
          await _storage.write(
              key: _demoDataKey,
              value: jsonEncode(DemoTrackingData.create(DateTime.now())));
        }
        await _storage.write(
            key: 'demo_tracking_enabled', value: enabled.toString());
        _demoMode = enabled;
      });

  Future<Map<String, dynamic>> getDailyLogs() async =>
      Map<String, dynamic>.from((await _guestData())['logs'] as Map);

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body, bool authenticated = true}) async {
    final request = http.Request(method, ApiConfig.endpoint(baseUrl, path));
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
      })()
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }
    if (response.statusCode == 401 && authenticated) {
      await _clearSession();
    }
    final dynamic data =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] : null;
      throw AccountException(detail is String
          ? detail
          : 'Request failed (${response.statusCode}). Check your inputs.');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<AccountUser> signIn(
          {required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<AccountUser> register(
          {required String name,
          required String email,
          required String password}) =>
      _authenticate('/auth/register',
          {'name': name, 'email': email, 'password': password});

  Future<void> requestPasswordReset(String email) async {
    await _request('POST', '/auth/forgot-password',
        body: {'email': email}, authenticated: false);
  }

  Future<void> resetPassword(String token, String password) async {
    await _request('POST', '/auth/reset-password',
        body: {'token': token, 'password': password}, authenticated: false);
  }

  Future<AccountUser> _authenticate(
      String path, Map<String, dynamic> body) async {
    final data = await _request('POST', path, body: body, authenticated: false);
    _token = data['access_token'] as String;
    await _storage.write(key: 'account_token', value: _token);
    currentUser =
        AccountUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
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

  Future<Map<String, dynamic>> getProfile() async {
    final data = await _guestData();
    return {
      ...Map<String, dynamic>.from(data['profile'] as Map),
      'uid': _guestUser.uid,
      'email': _guestUser.email
    };
  }

  Future<void> updateProfile(Map<String, dynamic> data) =>
      _writeGuestData(() async {
        final stored = await _guestData();
        stored['profile'] = {
          ...Map<String, dynamic>.from(stored['profile'] as Map),
          ...data,
          'updatedAt': DateTime.now().toUtc().toIso8601String()
        };
        await _storage.write(key: _activeDataKey, value: jsonEncode(stored));
      });

  Future<Map<String, dynamic>?> getDailyLog(String day) async {
    final stored = await _guestData();
    final log = (stored['logs'] as Map)[day];
    return log == null ? null : Map<String, dynamic>.from(log as Map);
  }

  Future<void> saveDailyLog(
          String day, Map<String, dynamic> log, Map<String, dynamic> profile) =>
      _writeGuestData(() async {
        final stored = await _guestData();
        final timestamp = DateTime.now().toUtc().toIso8601String();
        stored['logs'] = {
          ...Map<String, dynamic>.from(stored['logs'] as Map),
          day: {...log, 'timestamp': timestamp}
        };
        stored['profile'] = {
          ...Map<String, dynamic>.from(stored['profile'] as Map),
          ...profile,
          'updatedAt': timestamp
        };
        // One encrypted value preserves the log/profile update together offline.
        await _storage.write(key: _activeDataKey, value: jsonEncode(stored));
      });
}
