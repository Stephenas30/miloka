// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/screens/profile_screen.dart';

void main() {
  testWidgets('Profile screen shows user summary and stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: {
            'full_name': 'Ada',
            'email': 'ada@example.com',
            'username': 'ada',
            'coins': 120,
            'belote_played': 10,
            'belote_wins': 6,
            'belote_losses': 4,
            'ludo_played': 8,
            'ludo_wins': 2,
            'ludo_losses': 6,
          },
        ),
      ),
    );

    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Belote'), findsOneWidget);
    expect(find.text('Ludo'), findsOneWidget);
  });
}
