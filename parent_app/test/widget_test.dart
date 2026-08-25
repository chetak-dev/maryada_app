// Basic smoke test for the GuardNest parent app.

import 'package:flutter_test/flutter_test.dart';

import 'package:guardnest_parent/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const GuardNestApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    // Sign-up and the email form were removed; access comes from a site-admin
    // grant, so Google is the only way in.
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
