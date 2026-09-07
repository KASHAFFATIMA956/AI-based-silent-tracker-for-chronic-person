import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/admin_data_provider.dart';
import '../state/auth_provider.dart';
import '../state/doctor_data_provider.dart';
import '../state/language_provider.dart';
import '../state/patient_data_provider.dart';
import 'admin/people_screen.dart';
import 'auth/login_screen.dart';
import 'placeholder_screen.dart';
import '../widgets/doctor_shell.dart';
import '../widgets/patient_shell.dart';

/// The ONLY place that decides which screen a signed-in user lands on —
/// and it decides purely from `session.role` (sourced from the backend
/// JWT), never from which login form was used or any other user choice.
/// This is the routing half of the "no role-switcher" requirement — see
/// context/decisions-log.md.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _dataLoadStarted = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const _SplashScreen();
      case AuthStatus.signedOut:
        // Reset the once-per-sign-in guard (and any stale data from a
        // PREVIOUS session) so logging in again — as the same or a
        // different account — reliably reloads rather than silently
        // keeping whatever the last signed-in user last saw. Found and
        // fixed 2026-08-29 while wiring doctor routing into this same
        // switch: this flag previously lived for the lifetime of the
        // RootRouter widget (i.e. the whole app run, since RootRouter is
        // MaterialApp's `home:`), not "once per sign-in" as its own
        // comment claimed, and neither data provider's `reset()` was ever
        // called anywhere — see context/decisions-log.md.
        if (_dataLoadStarted) {
          _dataLoadStarted = false;
          context.read<PatientDataProvider>().reset();
          context.read<DoctorDataProvider>().reset();
          context.read<AdminDataProvider>().reset();
        }
        return const LoginScreen();
      case AuthStatus.signedIn:
        final session = auth.session!;

        if (session.role == 'doctor') {
          if (!_dataLoadStarted) {
            _dataLoadStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<DoctorDataProvider>().loadAll(session.userId);
            });
          }
          return const DoctorShell();
        }

        if (session.role == 'admin') {
          if (!_dataLoadStarted) {
            _dataLoadStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AdminDataProvider>().loadAll();
            });
          }
          return const PeopleScreen();
        }

        if (!session.isPatientOrAttendant) {
          // No other role exists besides patient/attendant/doctor/admin —
          // this is unreachable with real backend data, kept only as a
          // structural fallback rather than an assumed-dead branch.
          return const PlaceholderScreen();
        }
        if (session.patientId == null) {
          // A patient/attendant account with no linked Patient row yet —
          // shouldn't happen with real seed data, but fail visibly rather
          // than crash on a null patientId deeper in the tree.
          return const _UnlinkedAccountScreen();
        }
        // Kick off the initial data load exactly once per sign-in.
        if (!_dataLoadStarted) {
          _dataLoadStarted = true;
          context.read<LanguageProvider>().setFromAccountPreference(session.languagePreference);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<PatientDataProvider>().loadAll(session.patientId!);
          });
        }
        return const PatientShell();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _UnlinkedAccountScreen extends StatelessWidget {
  const _UnlinkedAccountScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'This account isn\'t linked to a patient record yet.\nAsk your clinic to finish setting up your profile.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
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
