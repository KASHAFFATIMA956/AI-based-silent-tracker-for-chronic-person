import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/admin_user.dart';
import '../../state/admin_data_provider.dart';
import '../../state/auth_provider.dart';
import 'user_form_screen.dart';

/// GET /admin/users — the admin home / "People & roles" screen, the only
/// admin screen this session builds (smallest remaining role scope, no
/// complex workflows — see context/progress.md). Content/layout source:
/// the web prototype's a-people screen (`UI Inspo/.../RozNoor.dc.html`),
/// adapted to mobile stacked cards instead of a table row grid — same
/// adaptation PatientRosterScreen made for d-patients. The prototype's
/// "Red-flag rule sets" card is decorative demo dressing with no backing
/// data (no endpoint exposes rule-set versions/review dates) — left out
/// rather than faked, same spirit as the doctor role's baseline-band-chart
/// omission (see context/decisions-log.md).
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  String _query = '';

  Future<void> _openCreate() async {
    // No return-value handling needed: AdminDataProvider.createUser already
    // appends the new row to the shared list on success (same convention
    // as DoctorDataProvider.addNote), so the list behind this screen
    // updates itself the moment the form pops.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UserFormScreen()),
    );
  }

  Future<void> _openEdit(AdminUser user) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => UserFormScreen(existing: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AdminDataProvider>();

    final filtered = _query.trim().isEmpty
        ? data.users
        : data.users.where((u) {
            final q = _query.trim().toLowerCase();
            return u.name.toLowerCase().contains(q) || u.phoneOrEmail.toLowerCase().contains(q);
          }).toList();

    Widget body;
    if (data.isLoading && data.users.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data.loadError != null && data.users.isEmpty) {
      body = _ErrorState(
        message: data.loadError!,
        onRetry: () => context.read<AdminDataProvider>().loadAll(),
      );
    } else if (filtered.isEmpty) {
      body = Center(
        child: Text(
          data.users.isEmpty ? 'No accounts yet.' : 'No one matches this search.',
          style: TextStyle(color: context.rnMuted(0.6)),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<AdminDataProvider>().refresh(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _PersonCard(user: filtered[i], onTap: () => _openEdit(filtered[i])),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('People & roles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Invite a person'),
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
                    'Accounts, disease tracks and clinician-reviewed rule sets',
                    style: TextStyle(color: context.rnMuted(0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name or phone/email',
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.user, required this.onTap});
  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
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
                        Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(
                          user.phoneOrEmail,
                          style: TextStyle(fontSize: 12, color: context.rnMuted(0.55)),
                        ),
                      ],
                    ),
                  ),
                  _RoleTag(role: user.role),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: context.rnMuted(0.4)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _meta(context, 'Linked to: ${user.linkedSummary ?? '—'}'),
                  if (user.diagnosis != null && user.diagnosis!.isNotEmpty)
                    _meta(context, user.diagnosis!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: 12, color: context.rnMuted(0.6)));
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: context.rnMuted(0.3)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${role[0].toUpperCase()}${role.substring(1)}',
        style: TextStyle(fontSize: 11, color: context.rnMuted(0.75), fontWeight: FontWeight.w600),
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
