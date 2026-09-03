import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/entry.dart';
import '../../state/patient_data_provider.dart';
import '../../widgets/risk_badge.dart';

/// GET /entries/{patient_id}/timeline — per the task spec. Used both as the
/// "Timeline" bottom tab (embedded in PatientShell) and as a screen pushed
/// on top of Result ("See my timeline").
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key, this.fromResult = false});

  final bool fromResult;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<PatientDataProvider>();

    Widget body;
    if (data.isLoading && data.timeline.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data.timeline.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No entries yet. Your first check-in will show up here.')),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<PatientDataProvider>().refreshTimeline(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          itemCount: data.timeline.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _TimelineTile(entry: data.timeline[i]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Timeline')),
      body: SafeArea(child: body),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(entry.riskResult?.riskLevel);
    final quote = entry.entryType == 'voice'
        ? (entry.rawTranscript ?? '')
        : 'Quick check-in — ${entry.medicineStatus == 'taken' ? 'medicine taken' : 'medicine missed'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(DateFormat('d').format(entry.timestamp), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                Text(DateFormat('MMM').format(entry.timestamp).toUpperCase(), style: TextStyle(fontSize: 11, color: context.rnMuted(0.55))),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.entryType == 'voice' ? 'Voice entry' : 'Quick check-in',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      RiskBadge(level: entry.riskResult?.riskLevel),
                      const Spacer(),
                      Text(DateFormat('h:mm a').format(entry.timestamp), style: TextStyle(fontSize: 12, color: context.rnMuted(0.5))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (quote.isNotEmpty)
                    Text(quote, style: TextStyle(fontSize: 14, color: context.rnMuted(0.8))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    children: [
                      if (entry.sleepValue != null) Text('Sleep ${entry.sleepValue!.toStringAsFixed(1)}h', style: _metaStyle(context)),
                      if (entry.energyValue != null) Text('Energy ${entry.energyValue!.toStringAsFixed(0)}/5', style: _metaStyle(context)),
                      if (entry.weightValue != null) Text('Weight ${entry.weightValue!.toStringAsFixed(1)}kg', style: _metaStyle(context)),
                      Text('Medicine ${entry.medicineStatus == 'taken' ? 'taken' : 'missed'}', style: _metaStyle(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _metaStyle(BuildContext context) =>
      TextStyle(fontSize: 12, color: context.rnMuted(0.6));
}
