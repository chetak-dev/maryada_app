// Basic smoke test for the GuardNest parent app.

import 'package:flutter_test/flutter_test.dart';

import 'package:guardnest_parent/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const GuardNestApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
