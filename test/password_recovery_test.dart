import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:femwise/screens/password_recovery_screen.dart';

void main() {
  testWidgets('Recovery blocks incomplete email and mismatched passwords',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordRecoveryScreen()));
    await tester.tap(find.text('Email recovery code'));
    await tester.pump();
    expect(find.text('Enter your email address.'), findsOneWidget);

    await tester.tap(find.text('I already have a recovery code'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'x' * 43);
    await tester.enterText(fields.at(1), 'new secure password');
    await tester.enterText(fields.at(2), 'different password');
    await tester.ensureVisible(find.text('Save new password'));
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(find.text('Please wait...'), findsNothing);
  });
}
