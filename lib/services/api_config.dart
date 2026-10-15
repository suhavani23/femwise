import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Addresses of the backend services, supplied when building/running Flutter.
class ApiConfig {
  static const _defaultAccounts = String.fromEnvironment('ACCOUNT_API_URL',
      defaultValue: 'https://femwise.onrender.com');
  static const _defaultPackagedFood =
      String.fromEnvironment('PACKAGED_FOOD_API_URL', defaultValue: '');
  static const _defaultCookedFood =
      String.fromEnvironment('COOKED_FOOD_API_URL', defaultValue: '');

  // The ingredient scanner uses the same deployed backend as anonymous sessions.
  static const foodAnalysisEnabled =
      bool.fromEnvironment('ENABLE_FOOD_ANALYSIS', defaultValue: true);
  static const cookedFoodAnalysisEnabled =
      bool.fromEnvironment('ENABLE_COOKED_FOOD_ANALYSIS', defaultValue: false);

  static const _storage = FlutterSecureStorage();
  static String? _cachedAccountsUrl;

  static Future<void> initialize() async {
    try {
      final saved = await _storage.read(key: 'custom_accounts_url');
      final uri = Uri.tryParse(saved ?? '');
      // Earlier APKs saved laptop addresses. Cloud builds must migrate these.
      _cachedAccountsUrl =
          uri?.scheme == 'https' && uri!.host.isNotEmpty ? saved : null;
    } catch (_) {}
  }

  static String get accounts => _cachedAccountsUrl ?? _defaultAccounts;
  static String get packagedFood =>
      _defaultPackagedFood.isEmpty ? accounts : _defaultPackagedFood;
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
      await _storage.write(
          key: 'custom_accounts_url', value: _cachedAccountsUrl);
    } catch (_) {}
  }

  static Uri endpoint(String base, String path) =>
      Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path');
}
