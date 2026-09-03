// Smoke test for the primary login screen's structure — the full app
// (test/../lib/main.dart) also reads flutter_secure_storage on startup,
// which has no platform channel in a plain widget test, so this test
// exercises LoginScreen directly instead of the whole RootRouter flow.
// End-to-end auth/routing behavior against the real backend is verified
// manually (see context/decisions-log.md, Flutter patient-app pass).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:roznoor_app/screens/auth/login_screen.dart';
import 'package:roznoor_app/state/auth_provider.dart';

void main() {
  testWidgets('Patient login screen shows the clinician-login link, not a role switcher', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('RozNoor'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Are you a doctor or admin? Log in here'), findsOneWidget);
    // The role-switcher tabs from the design prototype must never appear.
    expect(find.text('Doctor'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });
}
