import 'package:flutter/material.dart';

import '../../data/invites_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';
import '../home/home_shell.dart';

/// Professional sign-in / sign-up screen for guardians. UI-only for now (no
/// backend wired yet) — validates input and shows the intended flow.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  bool _isSignUp = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (email.isEmpty || !email.contains('@')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter your email above first.')),
      );
      return;
    }
    if (!AuthService.instance.isConfigured) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Password reset needs a connection.')),
      );
      return;
    }
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.friendlyError(e))),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // Real auth when Firebase is connected; otherwise falls through to demo.
      if (AuthService.instance.isConfigured) {
        if (_isSignUp) {
          // Stash any typed invite code so the role resolver can redeem it
          // once the account is created.
          InvitesRepository.instance.pendingCode = _invite.text.trim();
          await AuthService.instance.signUp(_email.text, _password.text);
        } else {
          await AuthService.instance.signIn(_email.text, _password.text);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.friendlyError(e))),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // In demo mode there's no auth stream to react to, so navigate directly.
    // When Firebase is connected, AuthGate reacts to the sign-in automatically.
    if (!AuthService.instance.isConfigured) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Center(child: const BrandMark(size: 76)),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _isSignUp
                        ? 'Set up Maryada to keep your family safe.'
                        : 'Sign in to manage your family’s devices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'you@example.com',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (v) {
                                final value = (v ?? '').trim();
                                if (value.isEmpty) return 'Enter your email';
                                if (!value.contains('@') || !value.contains('.')) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: '••••••••',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                if ((v ?? '').isEmpty) return 'Enter your password';
                                if ((v ?? '').length < 6) {
                                  return 'At least 6 characters';
                                }
                                return null;
                              },
                            ),
                            if (!_isSignUp) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _forgotPassword,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _invite,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: 'Invite code (optional)',
                                  hintText: 'From your administrator',
                                  prefixIcon: Icon(Icons.confirmation_num_outlined),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(_isSignUp ? 'Create account' : 'Sign in'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account?'
                            : 'New to Maryada?',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(_isSignUp ? 'Sign in' : 'Create account'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
