import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';
import '../home/home_shell.dart';

/// Sign-in for guardians. There is no self-service sign-up and no access code:
/// the site admin grants access to an email address, and that address signs in
/// with Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _signInWithGoogle() async {
    final messenger = ScaffoldMessenger.of(context);
    // No Firebase (demo mode): go straight to the sample dashboard.
    if (!AuthService.instance.isConfigured) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // A false result means the user dismissed the picker, which isn't a
      // failure worth reporting.
      await AuthService.instance.signInWithGoogle();
      // AuthGate reacts to the sign-in automatically.
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in to manage your family’s devices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _signInWithGoogle,
                            icon: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.g_mobiledata_rounded,
                                    size: 28),
                            label: const Text('Continue with Google'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Made with ❤️ by ISKCON Brahmapur',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted),
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
