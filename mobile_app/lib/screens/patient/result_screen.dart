import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/entry.dart';
import '../../state/patient_data_provider.dart';
import '../../widgets/chest_pain_first_aid_panel.dart';
import '../../widgets/risk_badge.dart';
import 'timeline_screen.dart';

/// Displays the risk_results returned from a POST /entries submission
/// (risk_level, risk_title, risk_message, reasoning) — per the task spec.
/// `symptom_names` (manually-ticked + AI-merged) stands in for the
/// prototype's "What we heard" card. The prototype's separate numeric
/// "Against your baseline" deltas card is omitted — `ai_results.deviation_
/// deltas` has no exposing endpoint (see context/decisions-log.md); the
/// same information already appears in prose inside `reasoning`.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final risk = entry.riskResult;
    final color = RnColors.forRiskLevel(risk?.riskLevel);
    final profile = context.watch<PatientDataProvider>().profile;
    // Wired at the display layer only, per the task's explicit
    // instruction — app/services/rules.py's scoring is unchanged. "Chest
    // pain" is the exact literal HEART_FAILURE_RULES["hard_red_symptoms"]
    // checks against, so this isolates the chest-pain hard flag from a
    // Red caused purely by the weight-gain hard flag.
    final showChestPainFirstAid = risk?.riskLevel == 'Red' && entry.symptomNames.contains('Chest pain');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your result'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(DateFormat('h:mm a').format(entry.timestamp))),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: color, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RiskDot(level: risk?.riskLevel),
                        const SizedBox(width: 10),
                        RiskBadge(level: risk?.riskLevel),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      risk?.riskTitle ?? 'Recorded',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600, color: color),
                    ),
                    const SizedBox(height: 10),
                    Text(risk?.riskMessage ?? '', style: const TextStyle(fontSize: 16, height: 1.5)),
                    if (risk?.reasoning != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        risk!.reasoning!,
                        style: TextStyle(fontSize: 14, color: context.rnMuted(0.7), height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showChestPainFirstAid) const ChestPainFirstAidPanel(),
            if (entry.symptomNames.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WHAT WE HEARD', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.symptomNames
                            .map((s) => Chip(
                                  label: Text(s),
                                  backgroundColor: RnColors.accent200,
                                  side: BorderSide.none,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Everyday words matched to tracked signals. Nothing was inferred beyond what you said.',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: context.rnMuted(0.55)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _showEmergencySheet(context, profile),
              icon: const Icon(Icons.local_hospital_outlined, color: RnColors.riskRed),
              label: const Text('Contact my doctor', style: TextStyle(color: RnColors.riskRed)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: RnColors.riskRed),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const TimelineScreen(fromResult: true)),
                (route) => route.isFirst,
              ),
              child: const Text('See my timeline'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmergencySheet(BuildContext context, dynamic profile) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile?.assignedDoctorName ?? 'Your care team',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(profile?.emergencyContactName ?? 'Emergency contact not set'),
              Text(
                profile?.emergencyContactPhone ?? '',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
