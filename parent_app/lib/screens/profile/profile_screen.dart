import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/user_repository.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/dialog_buttons.dart';

/// One profile screen for both site and org admins: shows the signed-in account
/// (login info) and lets them sign out. Admin tools live on the site-admin
/// console itself, not here.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.of(ctx).pop(false)),
          DialogConfirmButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: 'Sign out',
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (AuthService.instance.isConfigured) {
      await AuthService.instance.signOut();
    }
    navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: uid == null
          ? _body(context, null)
          : StreamBuilder<AppUser?>(
              stream: UserRepository.instance.watch(uid),
              builder: (context, snap) => _body(context, snap.data),
            ),
    );
  }

  Widget _body(BuildContext context, AppUser? u) {
    final theme = Theme.of(context);
    final email = u?.email ?? AuthService.instance.currentUser?.email ?? '—';
    final roleLabel = u == null
        ? 'Signed in'
        : u.isSiteAdmin
            ? 'Site admin'
            // Deliberately silent about view vs edit — the access level is
            // between the administrator and this app, not shown to parents.
            : u.isOrgAdmin
                ? 'Parent'
                : 'Account';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
      children: [
        // Login info.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(roleLabel,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Account', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
            title: const Text('Sign out',
                style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _signOut(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Text('Maryada · $kAppVersionLabel',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Text('Made with ❤️ by ISKCON Brahmapur',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}
