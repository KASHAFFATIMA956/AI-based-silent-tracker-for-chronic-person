import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/doctor/alerts_screen.dart';
import '../screens/doctor/patient_roster_screen.dart';
import '../state/doctor_data_provider.dart';

/// Bottom tab shell for the doctor role — Patients / Alerts. The web
/// prototype's d-patients/d-alerts are two independently-reachable
/// sidebar items; d-detail is reached only by opening a patient (tap), not
/// a tab of its own — see context/conventions.md's doctor/admin
/// design-source note. Adapted to a mobile bottom-tab bar (matching
/// PatientShell's own convention) rather than the prototype's sidebar.
class DoctorShell extends StatefulWidget {
  const DoctorShell({super.key});

  @override
  State<DoctorShell> createState() => _DoctorShellState();
}

class _DoctorShellState extends State<DoctorShell> {
  int _index = 0;

  static const _screens = [
    PatientRosterScreen(),
    AlertsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final unreviewed = context.watch<DoctorDataProvider>().unreviewedAlertCount;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: unreviewed > 0
                ? Badge(label: Text('$unreviewed'), child: const Icon(Icons.notifications_outlined))
                : const Icon(Icons.notifications_outlined),
            selectedIcon: unreviewed > 0
                ? Badge(label: Text('$unreviewed'), child: const Icon(Icons.notifications))
                : const Icon(Icons.notifications),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}
