import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:femwise/services/api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Existing laptop settings migrate to the deployed HTTPS service',
      () async {
    for (final previous in [
      '',
      'http://10.60.73.214:8002',
      'http://localhost:8002'
    ]) {
      FlutterSecureStorage.setMockInitialValues(
          {'custom_accounts_url': previous});
      await ApiConfig.initialize();
      expect(ApiConfig.accounts, 'https://femwise.onrender.com');
    }
    expect(ApiConfig.foodAnalysisEnabled, isTrue);
    expect(ApiConfig.packagedFood, ApiConfig.accounts);
    expect(ApiConfig.cookedFoodAnalysisEnabled, isFalse);
  });

  test('Intentional HTTPS custom servers remain available', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'custom_accounts_url': 'https://accounts.example.org'});
    await ApiConfig.initialize();
    expect(ApiConfig.endpoint(ApiConfig.accounts, '/health').toString(),
        'https://accounts.example.org/health');
  });
}
