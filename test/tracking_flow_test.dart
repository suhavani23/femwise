import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:femwise/main.dart';
import 'package:femwise/services/account_service.dart';
import 'package:femwise/screens/guide_run_screen.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {'demo_tracking_enabled': 'false'});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Offline startup, profile prefill and self-care navigation',
      (tester) async {
    final service = AccountService.instance;
    await service.initialize();
    await service.updateProfile({
      'lastPeriodStartDate': '2026-10-01',
      'averagePeriodDuration': 5,
      'typicalCycleLength': 29,
    });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(find.byTooltip('Cycle profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Cycle profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '29'), findsOneWidget);
    // Simulate the Android system Back to leave the profile editor.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    if (navigator.canPop()) navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.self_improvement));
    await tester.pumpAndSettle();
    expect(find.text('Stress'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    await tester.tap(find.text('Stress'));
    await tester.pumpAndSettle();
    expect(find.text('Stress Guides'), findsOneWidget);
    expect(find.text('Gentle Grounding & Breath Flow'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save and reopen a daily log without network access',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final notes = find.byType(TextFormField).last;
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'My offline daily note');
    await tester.ensureVisible(find.text('Save Daily Log'));
    await tester.tap(find.text('Save Daily Log'));
    await tester.pumpAndSettle();
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    expect((await AccountService.instance.getDailyLog(day))!['notes'],
        'My offline daily note');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'My offline daily note'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('All self-care instructions and image/model/music assets exist', () {
    for (final symptom in ['stress', 'anxiety', 'insomnia']) {
      final guides =
          jsonDecode(File('assets/jsons/$symptom.json').readAsStringSync())
              as List;
      expect(guides, isNotEmpty);
      for (final guide in guides) {
        for (final step in guide['steps']) {
          expect(step['instructions'], isNotEmpty);
          expect(step['duration_minutes'], greaterThan(0));
          expect(File(step['image'] as String).lengthSync(), greaterThan(0));
        }
      }
    }
    expect(File('assets/models/movenet_lightning.tflite').lengthSync(),
        greaterThan(1000));
    expect(File('assets/music.mp3').lengthSync(), greaterThan(1000));
  });

  testWidgets('Self-care timer completes once and resets for the next step',
      (tester) async {
    var completed = 0;
    Widget step(int index) => MaterialApp(
            home: BreathingStepWidget(
          key: ValueKey(index),
          step: const {'duration_minutes': 1},
          onStepCompleted: () => completed++,
        ));
    await tester.pumpWidget(step(0));
    await tester.pump(const Duration(seconds: 60));
    expect(completed, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(completed, 1);
    await tester.pumpWidget(step(1));
    expect(find.text('Remaining: 1:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
