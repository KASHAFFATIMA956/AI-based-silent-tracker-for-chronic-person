import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/doctor.dart';
import '../../state/doctor_data_provider.dart';
import '../../widgets/risk_badge.dart';
import 'patient_detail_screen.dart';

/// GET /doctors/{doctor_id}/alerts + POST /alerts/{alert_id}/review across
/// the doctor's own patients. Content/layout source: the web prototype's
/// d-alerts screen — see context/conventions.md.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _unreviewedOnly = true;
  final Set<int> _reviewing = {};

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DoctorDataProvider>();
    final alerts = _unreviewedOnly ? data.alerts.where((a) => !a.reviewed).toList() : data.alerts;

    Widget body;
    if (data.isLoading && data.alerts.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data.loadError != null && data.alerts.isEmpty) {
      body = Center(child: Text(data.loadError!, style: TextStyle(color: context.rnMuted(0.6))));
    } else if (alerts.isEmpty) {
      body = Center(
        child: Text(
          _unreviewedOnly ? 'No unreviewed alerts.' : 'No alerts yet.',
          style: TextStyle(color: context.rnMuted(0.6)),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<DoctorDataProvider>().refreshAlerts(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          itemCount: alerts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _AlertCard(
            alert: alerts[i],
            isReviewing: _reviewing.contains(alerts[i].id),
            onReview: () => _review(alerts[i]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text(
                    '${data.unreviewedAlertCount} unread',
                    style: TextStyle(color: context.rnMuted(0.6), fontSize: 13),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Unread')),
                      ButtonSegment(value: false, label: Text('All')),
                    ],
                    selected: {_unreviewedOnly},
                    onSelectionChanged: (s) => setState(() => _unreviewedOnly = s.first),
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

  Future<void> _review(AlertItem alert) async {
    setState(() => _reviewing.add(alert.id));
    try {
      await context.read<DoctorDataProvider>().reviewAlert(alert.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not mark this reviewed. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _reviewing.remove(alert.id));
    }
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.isReviewing, required this.onReview});
  final AlertItem alert;
  final bool isReviewing;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(alert.riskLevel);
    return Opacity(
      opacity: alert.reviewed ? 0.6 : 1.0,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(alert.patientName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  RiskBadge(level: alert.riskLevel),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, h:mm a').format(alert.createdAt),
                style: TextStyle(fontSize: 12, color: context.rnMuted(0.5)),
              ),
              const SizedBox(height: 8),
              Text(alert.alertText, style: TextStyle(fontSize: 14, color: context.rnMuted(0.9))),
              if (alert.sourceRule != null) ...[
                const SizedBox(height: 4),
                Text(
                  alert.sourceRule!,
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: context.rnMuted(0.5)),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!alert.reviewed)
                    OutlinedButton(
                      onPressed: isReviewing ? null : onReview,
                      child: isReviewing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Mark reviewed'),
                    )
                  else
                    Text('Reviewed', style: TextStyle(fontSize: 13, color: context.rnMuted(0.6))),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PatientDetailScreen(patientId: alert.patientId, patientName: alert.patientName),
                      ),
                    ),
                    child: const Text('Open patient'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
