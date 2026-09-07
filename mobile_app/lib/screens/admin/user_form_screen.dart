import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/admin_user.dart';
import '../../state/admin_data_provider.dart';

const _roles = ['patient', 'doctor', 'attendant', 'admin'];
const _languages = ['english', 'roman_urdu'];

String _roleLabel(String role) => '${role[0].toUpperCase()}${role.substring(1)}';
String _languageLabel(String lang) => lang == 'roman_urdu' ? 'Roman Urdu' : 'English';

/// One form for both creating a new user (any role) and editing an
/// existing one, per this session's "smallest remaining scope, no complex
/// workflows" instruction — reusing one screen rather than building two.
/// [existing] null => create mode (POST /admin/users, password required);
/// non-null => edit mode (PATCH /admin/users/{id} — name/role/
/// phone_or_email/language_preference only, no password field, matching
/// the backend's real supported fields — see context/api-contracts.md).
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.existing});

  final AdminUser? existing;

  bool get isEdit => existing != null;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _identifierCtrl;
  final _passwordCtrl = TextEditingController();
  late String _role;
  late String _language;
  bool _obscure = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _identifierCtrl = TextEditingController(text: existing?.phoneOrEmail ?? '');
    _role = existing?.role ?? 'patient';
    _language = existing?.languagePreference ?? 'english';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final provider = context.read<AdminDataProvider>();
    try {
      if (widget.isEdit) {
        await provider.updateUser(
          widget.existing!.id,
          name: _nameCtrl.text.trim(),
          role: _role,
          phoneOrEmail: _identifierCtrl.text.trim(),
          languagePreference: _language,
        );
      } else {
        await provider.createUser(
          name: _nameCtrl.text.trim(),
          role: _role,
          phoneOrEmail: _identifierCtrl.text.trim(),
          password: _passwordCtrl.text,
          languagePreference: _language,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEdit ? 'User updated.' : 'User created.')),
      );
    } on ApiException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit person' : 'Invite a person')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorText != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: RnColors.riskRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_errorText!, style: const TextStyle(color: RnColors.riskRed)),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.badge_outlined)),
                  items: _roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r))))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _identifierCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: widget.isEdit ? TextInputAction.next : TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Phone or email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a phone or email' : null,
                ),
                const SizedBox(height: 16),
                if (!widget.isEdit) ...[
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Set a password for this account' : null,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  // No password field in edit mode — PATCH /admin/users/{id}
                  // doesn't support changing it (see context/api-contracts.md);
                  // flag that plainly rather than silently omitting it.
                  Text(
                    "Password can't be changed here — this account keeps its existing password.",
                    style: TextStyle(fontSize: 12, color: context.rnMuted(0.6)),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration:
                      const InputDecoration(labelText: 'Language preference', prefixIcon: Icon(Icons.language)),
                  items: _languages
                      .map((l) => DropdownMenuItem(value: l, child: Text(_languageLabel(l))))
                      .toList(),
                  onChanged: (v) => setState(() => _language = v ?? _language),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(widget.isEdit ? 'Save changes' : 'Create user'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
