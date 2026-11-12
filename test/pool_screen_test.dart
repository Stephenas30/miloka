import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:miloka/providers/auth_provider.dart';
import 'package:miloka/screens/pool_screen.dart';

void main() {
  testWidgets('billard mode selection offers the Kadri play modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: PoolScreen()),
      ),
    );

    expect(find.text('Billard 🎱'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Multiplayer'), findsOneWidget);
    expect(find.text('En ligne'), findsOneWidget);
  });
}
