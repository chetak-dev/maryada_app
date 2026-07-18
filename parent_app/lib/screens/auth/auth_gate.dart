import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/user_repository.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/dialog_buttons.dart';
import '../admin/admin_home_screen.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Routes between the login screen, the admin console and the host dashboard
/// based on auth state and the account's role.
///
/// - Demo mode (no Firebase): shows the login screen, which opens the demo host
///   dashboard on submit.
/// - Connected: reacts to `authStateChanges`; on sign-in it resolves the
///   account role (admin by bootstrap email, otherwise host) and routes there.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isConfigured) {
      return const LoginScreen();
    }
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const BrandLoader();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return _RoleRouter(uid: user.uid, email: user.email ?? '');
      },
    );
  }
}

/// Resolves and then watches the signed-in account, routing by role.
class _RoleRouter extends StatefulWidget {
  const _RoleRouter({required this.uid, required this.email});
  final String uid;
  final String email;

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late final Future<AppUser> _resolve =
      UserRepository.instance.resolve(widget.uid, widget.email);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser>(
      future: _resolve,
      builder: (context, resolveSnap) {
        if (!resolveSnap.hasData) {
          if (resolveSnap.hasError) {
            // Couldn't resolve the role — fall back to the host dashboard so
            // the account is never locked out by a transient error.
            return HomeShell(uid: widget.uid);
          }
          return const BrandLoader();
        }
        return StreamBuilder<AppUser?>(
          stream: UserRepository.instance.watch(widget.uid),
          initialData: resolveSnap.data,
          builder: (context, snap) {
            final u = snap.data ?? resolveSnap.data!;
            if (u.isAdmin) return const AdminHomeScreen();
            if (u.suspended) return const _SuspendedScreen();
            return HomeShell(uid: widget.uid);
          },
        );
      },
    );
  }
}

class _SuspendedScreen extends StatelessWidget {
  const _SuspendedScreen();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime with your email.'),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.of(ctx).pop(false)),
          DialogConfirmButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: 'Sign out',
          ),
        ],
      ),
    );
    if (confirmed == true) await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.danger, size: 40),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Account suspended',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your access has been paused. Please contact your administrator.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
