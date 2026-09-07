import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_provider.dart';
import '../../state/patient_data_provider.dart';
import '../../widgets/bilingual_text.dart';
import '../../widgets/risk_badge.dart';
import '../messages_screen.dart';
import 'profile_screen.dart';
import 'quick_checkin_screen.dart';
import 'timeline_screen.dart';
import 'voice_diary_screen.dart';
import 'weekly_digest_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<PatientDataProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RozNoor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My Profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<PatientDataProvider>().refreshTimeline(),
        child: data.isLoading && data.profile == null
            ? const Center(child: CircularProgressIndicator())
            : data.loadError != null && data.profile == null
                ? _ErrorState(
                    message: data.loadError!,
                    onRetry: () {
                      final patientId = context.read<AuthProvider>().session?.patientId;
                      if (patientId != null) {
                        context.read<PatientDataProvider>().loadAll(patientId);
                      }
                    },
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      const BilingualText(
                        en: 'How are you feeling today?',
                        ur: 'Aaj aap kaise hain?',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.profile == null
                            ? ''
                            : 'Day ${data.profile!.dayCount} · baseline learned from ${data.timeline.length} entries',
                        style: TextStyle(color: context.rnMuted(0.6)),
                      ),
                      const SizedBox(height: 22),
                      _SpeakCard(onTap: () => _goVoice(context)),
                      const SizedBox(height: 16),
                      _StatusCard(latest: data.latestEntry),
                      const SizedBox(height: 16),
                      _NavCard(
                        kicker: '30 seconds',
                        title: 'Daily Check-in',
                        subtitle: 'Sleep, energy, mood, appetite, mobility, medicine',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QuickCheckinScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _NavCard(
                        kicker: 'History',
                        title: 'My Timeline',
                        subtitle: 'Every entry, day by day, in your own words',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TimelineScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _NavCard(
                        kicker: 'Care team',
                        title: 'Messages',
                        subtitle: data.profile?.assignedDoctorName != null
                            ? 'Chat with ${data.profile!.assignedDoctorName}'
                            : 'Chat with your assigned doctor',
                        onTap: () => _goMessages(context),
                      ),
                      const SizedBox(height: 12),
                      _NavCard(
                        kicker: 'This week',
                        title: 'Silent Trend digest',
                        subtitle: 'Quiet changes we noticed across seven days',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeeklyDigestScreen()),
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => _showEmergencySheet(context),
                        icon: const Icon(Icons.emergency_outlined, color: RnColors.riskRed),
                        label: const Text('Emergency', style: TextStyle(color: RnColors.riskRed)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: RnColors.riskRed),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'RozNoor supports you and your care team. It does not diagnose. '
                        'In an emergency, contact your doctor or emergency services immediately.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: context.rnMuted(0.55),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  void _goVoice(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceDiaryScreen()));
  }

  void _goMessages(BuildContext context) {
    final patientId = context.read<AuthProvider>().session?.patientId;
    if (patientId == null) return;
    final doctorName = context.read<PatientDataProvider>().profile?.assignedDoctorName ?? 'Your doctor';
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MessagesScreen(patientId: patientId, title: doctorName)),
    );
  }

  void _showEmergencySheet(BuildContext context) {
    final profile = context.read<PatientDataProvider>().profile;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Emergency contact', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(profile?.emergencyContactName ?? 'Not set'),
              Text(
                profile?.emergencyContactPhone ?? '',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Text(
                'If this is a medical emergency, call your local emergency number now.',
                style: TextStyle(color: context.rnMuted(0.6), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeakCard extends StatelessWidget {
  const _SpeakCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RnColors.accent, width: 1.5),
                ),
                child: const Icon(Icons.mic_none, size: 36, color: RnColors.accent),
              ),
              const SizedBox(height: 16),
              const BilingualText(
                en: 'Tap and speak',
                ur: 'Bol kar batayein',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('10 seconds is enough', style: TextStyle(color: context.rnMuted(0.55))),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.latest});
  final dynamic latest;

  @override
  Widget build(BuildContext context) {
    final risk = latest?.riskResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TODAY\'S STATUS', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
            const SizedBox(height: 10),
            if (latest == null)
              const Text('No entries yet — your first check-in starts your baseline.')
            else ...[
              Row(
                children: [
                  RiskDot(level: risk?.riskLevel),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      risk?.riskTitle ?? 'Recorded',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                risk?.riskMessage ?? '',
                style: TextStyle(color: context.rnMuted(0.75)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kicker.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: context.rnMuted(0.65))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Try again'))),
      ],
    );
  }
}
