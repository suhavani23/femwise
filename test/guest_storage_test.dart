import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:femwise/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Guest tracking works without an API and persists after initialization',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'demo_tracking_enabled': 'false'});
    final service = AccountService.instance;
    await service.initialize();
    expect(service.currentUser, isNotNull);
    expect((await service.getProfile())['name'], 'Guest');
    await service
        .updateProfile({'typicalCycleLength': 30, 'onboardingComplete': true});
    await service.saveDailyLog(
        '2026-10-15',
        {'date': '2026-10-15', 'notes': 'Saved offline'},
        {'currentCycleStatus': 'NOT_PERIOD'});
    await service.initialize();
    expect((await service.getProfile())['typicalCycleLength'], 30);
    expect(
        (await service.getDailyLog('2026-10-15'))!['notes'], 'Saved offline');
    expect(await service.getDailyLog('2026-10-16'), isNull);
    await service.saveDailyLog('2026-10-15', {'notes': 'Updated'},
        {'currentCycleStatus': 'NOT_PERIOD'});
    expect((await service.getDailyLog('2026-10-15'))!['notes'], 'Updated');
  });

  test('Overlapping profile and log saves retain every change', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'demo_tracking_enabled': 'false'});
    final service = AccountService.instance;
    await service.initialize();
    await Future.wait([
      service.updateProfile({'typicalCycleLength': 29}),
      service.saveDailyLog('2026-10-15', {'notes': 'First day'}, {}),
      service.saveDailyLog('2026-10-16', {'notes': 'Second day'}, {}),
      service.updateProfile({'averagePeriodDuration': 5}),
    ]);
    await service.initialize();
    expect((await service.getProfile())['typicalCycleLength'], 29);
    expect((await service.getProfile())['averagePeriodDuration'], 5);
    expect((await service.getDailyLog('2026-10-15'))!['notes'], 'First day');
    expect((await service.getDailyLog('2026-10-16'))!['notes'], 'Second day');
  });
}
