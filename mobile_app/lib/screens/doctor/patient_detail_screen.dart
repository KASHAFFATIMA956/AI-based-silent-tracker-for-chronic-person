import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/doctor.dart';
import '../../models/entry.dart';
import '../../state/doctor_data_provider.dart';
import '../../widgets/risk_badge.dart';
import '../../widgets/trend_chart.dart';
import '../messages_screen.dart';

/// Full patient detail for a doctor: check-in history/timeline (reusing
/// the same GET /entries/{patient_id}/timeline the patient app itself
/// calls), a raw-value trend chart per numeric metric, alert history, and
/// doctor notes (view existing + add new). Content/layout source: the web
/// prototype's d-detail screen (`UI Inspo/.../RozNoor.dc.html`), adapted
/// to mobile stacked cards — see context/conventions.md.
///
/// **On "baseline trend"**: the backend has no endpoint exposing
/// `baseline_history`'s min/max bands (see context/api-contracts.md) — the
/// prototype's shaded "learned normal" band on its Sleep/Weight charts
/// can't be reproduced without one. This screen instead charts the
/// patient's actual recorded values over time, which is the trend data
/// this backend scope actually makes available — see
/// context/decisions-log.md for the full note.
class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.patientId, required this.patientName});

  final int patientId;
  final String patientName;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DoctorDataProvider>().loadPatientDetail(widget.patientId);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DoctorDataProvider>();
    final profile = data.selectedPatient;
    final timeline = data.selectedTimeline; // newest first
    final chronological = timeline.reversed.toList();
    final notes = data.selectedNotes;
    final alertHistory = data.alerts.where((a) => a.patientId == widget.patientId).toList();
    final latestRisk = timeline.isNotEmpty ? timeline.first.riskResult?.riskLevel : null;

    Widget body;
    if (data.isLoadingDetail && profile == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data.detailError != null && profile == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.detailError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.read<DoctorDataProvider>().loadPatientDetail(widget.patientId),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else {
      final weightPoints = chronological
          .where((e) => e.weightValue != null)
          .map((e) => TrendPoint(e.timestamp, e.weightValue!))
          .toList();
      final sleepPoints = chronological
          .where((e) => e.sleepValue != null)
          .map((e) => TrendPoint(e.timestamp, e.sleepValue!))
          .toList();

      body = RefreshIndicator(
        onRefresh: () => context.read<DoctorDataProvider>().loadPatientDetail(widget.patientId),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.patientName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (profile?.age != null) '${profile!.age}',
                          if (profile?.mrNumber != null) profile!.mrNumber!,
                          if (profile?.diagnosis != null) profile!.diagnosis!,
                          if (profile != null) 'Day ${profile.dayCount}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 13, color: context.rnMuted(0.6)),
                      ),
                    ],
                  ),
                ),
                if (latestRisk != null) RiskBadge(level: latestRisk),
              ],
            ),
            const SizedBox(height: 20),
            if (weightPoints.length >= 2) ...[
              _TrendCard(title: 'Weight · kg', points: weightPoints, lineColor: RnColors.riskRed),
              const SizedBox(height: 16),
            ],
            if (sleepPoints.length >= 2) ...[
              _TrendCard(title: 'Sleep · hours', points: sleepPoints, lineColor: RnColors.accent),
              const SizedBox(height: 16),
            ],
            _SectionCard(
              title: 'Check-in history',
              child: timeline.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No entries yet.', style: TextStyle(color: context.rnMuted(0.6))),
                    )
                  : Column(children: timeline.map((e) => _EntryTile(entry: e)).toList()),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Alert history',
              child: alertHistory.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No alerts.', style: TextStyle(color: context.rnMuted(0.6))),
                    )
                  : Column(children: alertHistory.map((a) => _AlertHistoryTile(alert: a)).toList()),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Doctor notes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('No notes yet.', style: TextStyle(color: context.rnMuted(0.6))),
                    )
                  else
                    ...notes.map((n) => _NoteTile(note: n)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _showAddNoteSheet(context),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Add note'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            tooltip: 'Messages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MessagesScreen(patientId: widget.patientId, title: widget.patientName),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  void _showAddNoteSheet(BuildContext context) {
    final provider = context.read<DoctorDataProvider>();
    final patientId = widget.patientId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddNoteSheet(
        controller: _noteController,
        onSave: (text) async {
          await provider.addNote(patientId, text);
        },
      ),
    );
  }
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet({required this.controller, required this.onSave});
  final TextEditingController controller;
  final Future<void> Function(String text) onSave;

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(text);
      widget.controller.clear();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save this note. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add a note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Discussed weight trend, advised daily weigh-ins…'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: RnColors.riskRed, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save note'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: RnColors.accent)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.points, required this.lineColor});
  final String title;
  final List<TrendPoint> points;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: SizedBox(
        height: 120,
        child: TrendChart(points: points, lineColor: lineColor),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(entry.riskResult?.riskLevel);
    final label = entry.entryType == 'voice'
        ? (entry.rawTranscript?.isNotEmpty == true ? entry.rawTranscript! : 'Voice entry')
        : (entry.symptomNames.isEmpty ? 'Quick check-in' : entry.symptomNames.join(', '));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              DateFormat('MMM d').format(entry.timestamp),
              style: TextStyle(fontSize: 12, color: context.rnMuted(0.6)),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
  Text(label, style: const TextStyle(fontSize: 14)),
                  // Added 2026-09-07 — optional home-monitoring readings,
                  // visible to the doctor whenever a patient logged one.
                  // Persisted only, not yet part of risk_result — see
                  // context/api-contracts.md.
                  if ((entry.systolicBp != null && entry.diastolicBp != null) ||
                      entry.bloodSugarMgDl != null) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (entry.systolicBp != null && entry.diastolicBp != null)
                          Text('BP ${entry.systolicBp}/${entry.diastolicBp}',
                              style: TextStyle(fontSize: 12, color: context.rnMuted(0.6))),
                        if (entry.bloodSugarMgDl != null)
                          Text('Sugar ${entry.bloodSugarMgDl} mg/dL',
                              style: TextStyle(fontSize: 12, color: context.rnMuted(0.6))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RiskBadge(level: entry.riskResult?.riskLevel),
                      if (entry.riskResult?.reasoning != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.riskResult!.reasoning!,
                            style: TextStyle(fontSize: 12, color: context.rnMuted(0.6)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
}

class _AlertHistoryTile extends StatelessWidget {
  const _AlertHistoryTile({required this.alert});
  final AlertItem alert;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(alert.riskLevel);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alert.alertText, style: const TextStyle(fontSize: 14)),
          Text(
            '${DateFormat('MMM d, h:mm a').format(alert.createdAt)}${alert.reviewed ? ' · reviewed' : ' · unreviewed'}',
            style: TextStyle(fontSize: 12, color: context.rnMuted(0.55)),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});
  final DoctorNote note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.noteText, style: const TextStyle(fontSize: 14)),
          Text(
            '${note.doctorName} · ${DateFormat('MMM d, h:mm a').format(note.createdAt)}',
            style: TextStyle(fontSize: 12, color: context.rnMuted(0.55)),
          ),
        ],
      ),
    );
  }
}
