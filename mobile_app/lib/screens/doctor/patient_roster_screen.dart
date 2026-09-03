import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/doctor.dart';
import '../../state/auth_provider.dart';
import '../../state/doctor_data_provider.dart';
import '../../widgets/risk_badge.dart';
import 'patient_detail_screen.dart';

/// GET /doctors/{doctor_id}/patients — the doctor home / patient roster.
/// Content/layout source: the web prototype's d-patients screen
/// (`UI Inspo/.../RozNoor.dc.html`), adapted to mobile stacked cards
/// instead of a table row grid — see context/conventions.md.
class PatientRosterScreen extends StatefulWidget {
  const PatientRosterScreen({super.key});

  @override
  State<PatientRosterScreen> createState() => _PatientRosterScreenState();
}

class _PatientRosterScreenState extends State<PatientRosterScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DoctorDataProvider>();
    final needsAttention =
        data.roster.where((p) => p.latestRiskLevel != null && p.latestRiskLevel != 'Green').length;

    final filtered = _query.trim().isEmpty
        ? data.roster
        : data.roster.where((p) {
            final q = _query.trim().toLowerCase();
            return p.name.toLowerCase().contains(q) || (p.mrNumber ?? '').toLowerCase().contains(q);
          }).toList();

    Widget body;
    if (data.isLoading && data.roster.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data.loadError != null && data.roster.isEmpty) {
      body = _ErrorState(
        message: data.loadError!,
        onRetry: () {
          final doctorId = context.read<AuthProvider>().session?.userId;
          if (doctorId != null) context.read<DoctorDataProvider>().loadAll(doctorId);
        },
      );
    } else if (filtered.isEmpty) {
      body = Center(
        child: Text(
          data.roster.isEmpty ? 'No patients assigned yet.' : 'No patients match this search.',
          style: TextStyle(color: context.rnMuted(0.6)),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<DoctorDataProvider>().refreshRoster(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _PatientCard(item: filtered[i]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data.roster.length} monitored · $needsAttention need attention',
                    style: TextStyle(color: context.rnMuted(0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name or MR number',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.item});
  final DoctorPatientRosterItem item;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(item.latestRiskLevel);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientDetailScreen(patientId: item.patientId, patientName: item.name),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(
                          '${item.mrNumber ?? '—'}${item.age != null ? ' · ${item.age}' : ''}',
                          style: TextStyle(fontSize: 12, color: context.rnMuted(0.55)),
                        ),
                      ],
                    ),
                  ),
                  RiskBadge(level: item.latestRiskLevel),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _meta(context, item.diagnosis ?? 'No diagnosis on file'),
                  _meta(context, 'Day ${item.dayCount}'),
                  _meta(
                    context,
                    item.lastEntryTimestamp == null
                        ? 'No entries yet'
                        : DateFormat('MMM d, h:mm a').format(item.lastEntryTimestamp!),
                  ),
                ],
              ),
              if (item.latestReasoning != null && item.latestReasoning!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.latestReasoning!, style: TextStyle(fontSize: 13, color: context.rnMuted(0.85))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: 12, color: context.rnMuted(0.6)));
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
