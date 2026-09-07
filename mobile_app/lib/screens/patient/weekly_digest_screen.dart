import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/entry.dart';
import '../../state/patient_data_provider.dart';

/// "Weekly Trends" — the task asks this be wired to real API calls rather
/// than mock data. There is no dedicated weekly-digest backend endpoint yet
/// (`weekly_digests` is a stored table with no route reading/writing it —
/// see context/progress.md, "Not yet started"), so this screen computes its
/// own week-over-week view entirely from real GET /entries/{id}/timeline
/// data already loaded — still real data, just aggregated client-side
/// instead of fabricated. See context/decisions-log.md.
class WeeklyDigestScreen extends StatelessWidget {
  const WeeklyDigestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final timeline = context.watch<PatientDataProvider>().timeline;
    final digest = _WeekDigest.compute(timeline);

    return Scaffold(
      appBar: AppBar(title: const Text('This week')),
      body: SafeArea(
        child: timeline.isEmpty
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No entries yet — trends will appear once you have a week of check-ins.'),
              ))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text(
                    digest.rangeLabel,
                    style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: RnColors.accent),
                  ),
                  const SizedBox(height: 6),
                  const Text('What quietly changed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  ...digest.insights.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: i.color, width: 2),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.kicker.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: i.color)),
                                const SizedBox(height: 6),
                                Text(i.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      )),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SLEEP, LAST 7 NIGHTS', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 110,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: digest.sleepBars
                                  .map((b) => Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 3),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text(b.value == null ? '—' : b.value!.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
                                              const SizedBox(height: 4),
                                              Container(
                                                height: (b.value ?? 0) * 10,
                                                decoration: BoxDecoration(
                                                  color: RnColors.accent300,
                                                  border: Border.all(color: RnColors.accent),
                                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(b.label, style: const TextStyle(fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: RnColors.accent300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('VS LAST WEEK', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 24,
                            runSpacing: 14,
                            children: digest.changed
                                .map((c) => SizedBox(
                                      width: 130,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(c.value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: c.color)),
                                          Text(c.label, style: TextStyle(fontSize: 12, color: context.rnMuted(0.65))),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SleepBar {
  _SleepBar(this.label, this.value);
  final String label;
  final double? value;
}

class _ChangedStat {
  _ChangedStat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
}

class _Insight {
  _Insight(this.kicker, this.text, this.color);
  final String kicker;
  final String text;
  final Color color;
}

class _WeekDigest {
  _WeekDigest({
    required this.rangeLabel,
    required this.sleepBars,
    required this.changed,
    required this.insights,
  });

  final String rangeLabel;
  final List<_SleepBar> sleepBars;
  final List<_ChangedStat> changed;
  final List<_Insight> insights;

  static _WeekDigest compute(List<Entry> timeline) {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 6));
    final prevWeekStart = now.subtract(const Duration(days: 13));

    final thisWeek = timeline.where((e) => e.timestamp.isAfter(weekStart.subtract(const Duration(days: 1)))).toList();
    final lastWeek = timeline
        .where((e) =>
            e.timestamp.isAfter(prevWeekStart.subtract(const Duration(days: 1))) &&
            e.timestamp.isBefore(weekStart))
        .toList();

    final bars = <_SleepBar>[];
    for (var i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final match = thisWeek.where((e) =>
          e.timestamp.year == day.year && e.timestamp.month == day.month && e.timestamp.day == day.day && e.sleepValue != null);
      final val = match.isEmpty ? null : match.first.sleepValue;
      bars.add(_SleepBar(DateFormat('E').format(day).substring(0, 1), val));
    }

    double? avg(Iterable<double?> values) {
      final v = values.whereType<double>().toList();
      if (v.isEmpty) return null;
      return v.reduce((a, b) => a + b) / v.length;
    }

    final sleepAvgThis = avg(thisWeek.map((e) => e.sleepValue));
    final sleepAvgLast = avg(lastWeek.map((e) => e.sleepValue));
    final energyAvgThis = avg(thisWeek.map((e) => e.energyValue));

    int adherencePct(List<Entry> entries) {
      if (entries.isEmpty) return 0;
      final taken = entries.where((e) => e.medicineStatus == 'taken').length;
      return ((taken / entries.length) * 100).round();
    }

    final adherenceThis = adherencePct(thisWeek);
    final adherenceLast = adherencePct(lastWeek);

    String delta(double? a, double? b, {String unit = ''}) {
      if (a == null || b == null) return '—';
      final d = a - b;
      final sign = d >= 0 ? '+' : '';
      return '$sign${d.toStringAsFixed(1)}$unit';
    }

    final changed = <_ChangedStat>[
      _ChangedStat(
        sleepAvgThis == null ? '—' : '${sleepAvgThis.toStringAsFixed(1)}h',
        'Avg sleep this week',
        RnColors.accentDark,
      ),
      _ChangedStat(
        delta(sleepAvgThis, sleepAvgLast, unit: 'h'),
        'Change vs last week',
        (sleepAvgThis ?? 0) < (sleepAvgLast ?? 999) ? RnColors.riskAmber : RnColors.riskGreen,
      ),
      _ChangedStat(
        energyAvgThis == null ? '—' : energyAvgThis.toStringAsFixed(1),
        'Avg energy (1-5)',
        RnColors.accentDark,
      ),
      _ChangedStat(
        '$adherenceThis%',
        'Medicine adherence',
        adherenceThis >= adherenceLast ? RnColors.riskGreen : RnColors.riskAmber,
      ),
    ];

    final insights = <_Insight>[];
    final worstThisWeek = thisWeek
        .where((e) => e.riskResult != null && e.riskResult!.riskLevel != 'Green')
        .toList();
    if (worstThisWeek.isNotEmpty) {
      insights.add(_Insight(
        '${worstThisWeek.length} entr${worstThisWeek.length == 1 ? 'y' : 'ies'} flagged',
        'This week had ${worstThisWeek.length} entr${worstThisWeek.length == 1 ? 'y' : 'ies'} above your usual pattern.',
        RnColors.forRiskLevel(worstThisWeek.first.riskResult!.riskLevel),
      ));
    }
    if (sleepAvgThis != null && sleepAvgLast != null && sleepAvgThis < sleepAvgLast - 0.5) {
      insights.add(_Insight(
        'Sleep',
        'Sleep averaged ${sleepAvgThis.toStringAsFixed(1)}h this week, down from ${sleepAvgLast.toStringAsFixed(1)}h last week.',
        RnColors.riskAmber,
      ));
    }
    if (adherenceThis < 100 && thisWeek.isNotEmpty) {
      insights.add(_Insight(
        'Medicine',
        'Medicine was taken on $adherenceThis% of logged days this week.',
        adherenceThis < 80 ? RnColors.riskCoral : RnColors.accent,
      ));
    }
    if (insights.isEmpty) {
      insights.add(_Insight('Stable week', 'Nothing stood out this week — everything stayed close to your usual pattern.', RnColors.riskGreen));
    }

    return _WeekDigest(
      rangeLabel: '${DateFormat('d MMM').format(weekStart)} – ${DateFormat('d MMM').format(now)}',
      sleepBars: bars,
      changed: changed,
      insights: insights,
    );
  }
}
