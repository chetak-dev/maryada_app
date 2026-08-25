import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/user_repository.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/parent_update.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
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
  void initState() {
    super.initState();
    // Signed in — this is the one moment we know a screen is about to appear,
    // so it's where the app asks whether a newer build has been published.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ParentUpdate.promptIfAvailable(context);
    });
  }

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
            // Also mirrored into the static fallback: pushed routes don't sit
            // under the AccessScope below, and must never default to editable
            // for a view-only account.
            AccessScope.fallback = u.isSiteAdmin || u.canEdit;
            if (u.isSiteAdmin) return const AdminHomeScreen();
            if (u.suspended) return const _SuspendedScreen();
            if (!u.hasAccess) return const _PendingAccessScreen();
            return AccessScope(
              canEdit: u.canEdit,
              child: HomeShell(uid: widget.uid),
            );
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
                    ?.copyWith(color: AppColors.textSecondaryOf(context)),
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

/// Shown to a signed-in account that hasn't been granted access yet. They must
/// wait for the site admin to grant them view or edit access.
class _PendingAccessScreen extends StatelessWidget {
  const _PendingAccessScreen();

  Future<void> _signOut(BuildContext context) async {
    if (AuthService.instance.isConfigured) {
      await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = AuthService.instance.currentUser?.email ?? '';
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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Access pending',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                email.isEmpty
                    ? 'Your account isn’t authorised yet. Ask the site admin to '
                        'grant you access.'
                    : 'Your account ($email) isn’t authorised yet. Ask the site '
                        'admin to grant you view or edit access.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryOf(context)),
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
