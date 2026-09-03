import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_provider.dart';
import '../../widgets/bilingual_text.dart';
import '../root_router.dart';

/// ONE login form, calling the same POST /auth/login either way — see
/// context/decisions-log.md ("no duplicate auth logic"). [isClinician]
/// only changes copy/accent color; it never changes which endpoint is
/// called or how the response is handled. Post-login routing is decided
/// entirely by RootRouter from the JWT's role, never by which entry point
/// the user tapped — see context/decisions-log.md ("role-switcher removal").
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.isClinician = false});

  final bool isClinician;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_identifierCtrl.text.trim(), _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      // Role-based routing only — RootRouter reads auth.session.role.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RootRouter()),
        (route) => false,
      );
    } else if (auth.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.lastError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isClinician ? clinicalAccent : RnColors.accent;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'RozNoor',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: accent,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Silent symptom & personal baseline monitoring',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: accent.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (widget.isClinician) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: clinicalAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'CLINICIAN SIGN-IN',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                            color: clinicalAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Doctor & admin sign in',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Use your clinic-issued credentials. You'll land on your dashboard automatically.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.rnMuted(0.6)),
                      ),
                    ] else ...[
                      // Exclusive, not bilingual-mixed: shows ONE of the two
                      // greeting strings depending on the language toggle,
                      // never both stacked together. Previously this was two
                      // separate always-visible Text widgets (Roman Urdu
                      // followed by English) — fixed 2026-08-27, see
                      // context/decisions-log.md.
                      BilingualText(
                        en: 'How are you feeling today?',
                        ur: 'Aaj aap kaise hain?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in to log your daily check-in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.rnMuted(0.55)),
                      ),
                    ],
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _identifierCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone or email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter your phone or email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 26),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Log in'),
                    ),
                    const SizedBox(height: 28),
                    if (!widget.isClinician)
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LoginScreen(isClinician: true)),
                            );
                          },
                          child: const Text(
                            'Are you a doctor or admin? Log in here',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to patient sign in', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
