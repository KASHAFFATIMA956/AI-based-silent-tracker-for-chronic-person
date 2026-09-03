import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_provider.dart';
import '../../state/language_provider.dart';
import '../../state/patient_data_provider.dart';
import '../../state/theme_provider.dart';

/// Profile — real patient data (GET /patients/{id} + GET /auth/me),
/// view-only: there is no PATCH /patients/{id} or PATCH /auth/me endpoint,
/// so "edit where the API supports it" currently means no field is
/// editable from here. See context/decisions-log.md.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<PatientDataProvider>().profile;
    final session = auth.session;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SafeArea(
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text(
                    'Set once with your attendant. Everything here shapes which safety rules apply to you.',
                    style: TextStyle(color: context.rnMuted(0.65)),
                  ),
                  const SizedBox(height: 18),
                  _SectionCard(
                    title: 'Person',
                    rows: [
                      _row('Full name', session?.name ?? '—'),
                      _row('Age', profile.age?.toString() ?? '—'),
                      _row('Attendant', profile.attendantName ?? '—'),
                      _row('Language preference', session?.languagePreference == 'roman_urdu' ? 'Roman Urdu' : 'English'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Condition',
                    rows: [
                      _row('Diagnosis', profile.diagnosis ?? '—'),
                      _row('MR number', profile.mrNumber ?? '—'),
                      _row('Treating doctor', profile.assignedDoctorName ?? '—'),
                      _row('Emergency contact', '${profile.emergencyContactName ?? '—'} · ${profile.emergencyContactPhone ?? ''}'),
                    ],
                    extra: profile.medicationList.isEmpty
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 28),
                              const Text('MEDICINES', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: profile.medicationList
                                    .map((m) => Chip(label: Text(m), backgroundColor: RnColors.accent100, side: const BorderSide(color: RnColors.divider)))
                                    .toList(),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: RnColors.accent300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BASELINE STATUS', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
                          const SizedBox(height: 10),
                          Text(profile.baselineStageLabel, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: (profile.dayCount / 15).clamp(0, 1).toDouble(),
                              minHeight: 6,
                              backgroundColor: RnColors.accent100,
                              color: RnColors.accent400,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Day ${profile.dayCount} of monitoring. Days 1-7 collect your first ranges, days 8-14 learn them. '
                            'From day 15 your deviations are measured against your own history.',
                            style: TextStyle(fontSize: 14, color: context.rnMuted(0.7)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Roman Urdu', style: TextStyle(fontSize: 15)),
                      Switch(
                        value: context.watch<LanguageProvider>().isRomanUrdu,
                        onChanged: (v) => context.read<LanguageProvider>().setRomanUrdu(v),
                        activeTrackColor: RnColors.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _ThemeToggleRow(),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () => _logout(context),
                    child: const Text('Log out'),
                  ),
                ],
              ),
      ),
    );
  }

  static _ProfileRow _row(String label, String value) => _ProfileRow(label, value);

  /// Profile is reached by pushing on top of the patient shell (see
  /// widgets/patient_shell.dart), so signing out here has to unwind that
  /// pushed route first — RootRouter (the app's single `home:` widget)
  /// reacting to AuthProvider's state change alone only swaps what the
  /// FIRST route renders; it can't dismiss routes already pushed on top
  /// of it. Without this, logging out from Profile left the Profile
  /// screen visibly on-screen instead of returning to the login screen —
  /// caught during this session's real-backend verification pass (see
  /// context/decisions-log.md).
  void _logout(BuildContext context) {
    context.read<AuthProvider>().logout();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _ProfileRow {
  _ProfileRow(this.label, this.value);
  final String label;
  final String value;
}

/// Paper (light) / Nocturne (dark) toggle — matches the prototype's own
/// "Paper"/"Nocturne" radio pair (`RozNoor.dc.html`). Uses SegmentedButton
/// rather than a Switch (unlike the language row above) since these are two
/// named options, not an on/off state.
class _ThemeToggleRow extends StatelessWidget {
  const _ThemeToggleRow();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Appearance', style: TextStyle(fontSize: 15)),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Paper')),
            ButtonSegment(value: true, label: Text('Nocturne')),
          ],
          selected: {themeProvider.isDark},
          onSelectionChanged: (s) => context.read<ThemeProvider>().setDark(s.first),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.rows, this.extra});

  final String title;
  final List<_ProfileRow> rows;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
            const SizedBox(height: 14),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.label, style: TextStyle(fontSize: 12, color: context.rnMuted(0.55))),
                      const SizedBox(height: 2),
                      Text(r.value, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                )),
            if (extra != null) extra!,
          ],
        ),
      ),
    );
  }
}
