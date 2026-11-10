import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/screens/pool_screen.dart';

void main() {
  testWidgets(
    'billard mode selection offers the original play modes',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PoolScreen()));

      expect(find.text('BILLARD 8'), findsOneWidget);
      expect(find.text('SOLO'), findsOneWidget);
      expect(find.text('À DEUX'), findsOneWidget);
      expect(find.text('EN RÉSEAU LOCAL'), findsOneWidget);
    },
  );
}
