import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_provider.dart';

/// Dead-code fallback now that doctor (2026-08-29) and admin (2026-08-29,
/// later same day) both have real screens — every real role/RootRouter
/// branch bypasses this. Kept only as a structural safety net for a role
/// value this app doesn't otherwise expect, never actually reached with
/// real backend data. See lib/screens/root_router.dart.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.session?.role ?? '';
    final name = auth.session?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('RozNoor')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dashboard_customize_outlined, size: 52, color: clinicalAccent),
              const SizedBox(height: 20),
              Text(
                'Welcome, $name',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'The ${role[0].toUpperCase()}${role.substring(1)} dashboard is built in a later phase of this app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.rnMuted()),
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
