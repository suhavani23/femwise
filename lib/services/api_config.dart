import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Addresses of the backend services, supplied when building/running Flutter.
class ApiConfig {
  static const _defaultAccounts = String.fromEnvironment('ACCOUNT_API_URL',
      defaultValue: 'http://10.60.73.214:8002');
  static const _defaultPackagedFood = String.fromEnvironment('PACKAGED_FOOD_API_URL',
      defaultValue: 'http://10.60.73.214:8000');
  static const _defaultCookedFood = String.fromEnvironment('COOKED_FOOD_API_URL',
      defaultValue: 'http://10.60.73.214:8001');

  static const _storage = FlutterSecureStorage();
  static String? _cachedAccountsUrl;

  static Future<void> initialize() async {
    try {
      _cachedAccountsUrl = await _storage.read(key: 'custom_accounts_url');
    } catch (_) {}
  }

  static String get accounts => _cachedAccountsUrl ?? _defaultAccounts;
  static String get packagedFood => _defaultPackagedFood;
  static String get cookedFood => _defaultCookedFood;

  static Future<void> setAccountsUrl(String url) async {
    var trimmed = url.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    _cachedAccountsUrl = trimmed;
    try {
      await _storage.write(key: 'custom_accounts_url', value: _cachedAccountsUrl);
    } catch (_) {}
  }

  static Uri endpoint(String base, String path) =>
      Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path');
}
