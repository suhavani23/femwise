import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:femwise/services/account_service.dart';
import 'package:femwise/services/ingredient_service.dart';
import 'package:femwise/food_options/food_options_screen.dart';
import 'package:femwise/packed_food/pack_foods_scan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final review = {'summary': 'Oats are listed.', 'ingredients': [
    {'name': 'Oats', 'category': 'whole_food', 'note': 'A listed grain.'}],
    'limitations': ['Amounts are unknown.'], 'disclaimer': 'AI review, not medical advice.'};

  test('Sends OCR to deployed route, renews expired anonymous session and displays review', () async {
    var calls = 0;
    final refreshed = <bool>[];
    final client = MockClient((request) async {
      calls++;
      expect(request.url.toString(), 'https://femwise.onrender.com/extract_ingredients');
      expect(jsonDecode(request.body)['text'], 'Ingredients: oats');
      expect(request.headers['Authorization'], calls == 1 ? 'Bearer old' : 'Bearer fresh');
      return calls == 1 ? http.Response('{}', 401) : http.Response(jsonEncode(review), 200);
    });
    final service = IngredientService(client: client, authorization: (refresh) async {
      refreshed.add(refresh);
      return {'Authorization': refresh ? 'Bearer fresh' : 'Bearer old'};
    });
    final result = await service.analyze(' Ingredients: oats ');
    expect(refreshed, [false, true]);
    expect(result, contains('Oats (whole food)'));
    expect(result, contains('Amounts are unknown.'));
    expect(result, contains('not medical advice'));
    client.close();
  });

  test('Missing deployment and HTML server errors have readable messages', () async {
    for (final status in [404, 503]) {
      final client = MockClient((_) async => http.Response('<html>Unavailable</html>', status));
      final service = IngredientService(client: client, authorization: (_) async => {});
      await expectLater(service.analyze('oats'), throwsA(isA<AccountException>()));
      client.close();
    }
  });

  testWidgets('Scanner remains accessible without a camera and offers typed input', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'), (_) async => <dynamic>[]);
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: FoodOptionsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Scan Ingredients'), findsOneWidget);
    expect(find.text('Analyze Cooked Food'), findsNothing);
    await tester.tap(find.text('Scan Ingredients'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageToTextScreen), findsOneWidget);
    expect(find.textContaining('Camera unavailable.'), findsOneWidget);
    await tester.tap(find.text('Enter / edit ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Enter ingredients'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Oats, milk');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
