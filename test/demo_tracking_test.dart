import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:femwise/services/account_service.dart';
import 'package:femwise/services/demo_tracking_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Five sample cycles span five months and include irregular gaps', () {
    final demo = DemoTrackingData.create(DateTime(2026, 10, 15));
    final logs = (demo['logs'] as Map).values.cast<Map>();
    final starts = logs.where((log) => log['menstrualDay'] == 1)
        .map((log) => DateTime.parse(log['date'] as String)).toList()..sort();
    expect(starts.length, 5);
    expect(starts.last.difference(starts.first).inDays, 154);
    expect(starts.first, DateTime(2026, 5, 4));
    expect(logs.every((log) => log['isDemo'] == true), isTrue);
  });
  test('Demo records remain separate from real records across restarts', () async {
    FlutterSecureStorage.setMockInitialValues({'demo_tracking_enabled': 'false'});
    final service = AccountService.instance;
    await service.initialize();
    await service.updateProfile({'name': 'Real profile'});
    await service.saveDailyLog('2026-10-15', {'notes': 'Real note'}, {});
    await service.setDemoMode(true);
    expect((await service.getProfile())['isDemo'], isTrue);
    expect((await service.getDailyLogs()).length, greaterThan(20));
    await service.initialize();
    expect(service.demoMode, isTrue);
    await service.setDemoMode(false);
    expect((await service.getProfile())['name'], 'Real profile');
    expect((await service.getDailyLog('2026-10-15'))!['notes'], 'Real note');
  });
}
