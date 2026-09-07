import 'package:flutter/material.dart';

import '../screens/patient/home_screen.dart';
import '../screens/patient/timeline_screen.dart';
import '../screens/patient/voice_diary_screen.dart';
import '../screens/patient/weekly_digest_screen.dart';

/// Bottom tab shell for the four always-reachable patient screens — matches
/// the mobile prototype's nav bar exactly (Home / Speak / Timeline /
/// Trends, `RozNoor.dc.html`'s `.rn-tab` row). Quick Check-in, Result, and
/// Profile are reached by pushing on top of this shell (same as the
/// prototype, where those screens use a back arrow instead of a persistent
/// tab), not additional tabs.
class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    VoiceDiaryScreen(embedded: true),
    TimelineScreen(),
    WeeklyDigestScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.mic_none_outlined), selectedIcon: Icon(Icons.mic), label: 'Speak'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Timeline'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Trends'),
        ],
      ),
    );
  }
}
