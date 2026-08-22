import 'package:flutter/material.dart';

import '../../data/user_repository.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/dialog_buttons.dart';
import '../admin/admin_tools_screen.dart';

/// One profile screen for both site and org admins: shows the signed-in account
/// (login info) and role-appropriate actions — for a site admin: web filtering,
/// publish app update and clear data — plus sign out.
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
    final isSiteAdmin = u?.isSiteAdmin ?? false;
    final roleLabel = u == null
        ? 'Signed in'
        : u.isSiteAdmin
            ? 'Site admin'
            : u.isOrgAdmin
                ? 'Parent · ${u.access == AccessLevel.edit ? 'Edit access' : 'View only'}'
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
        if (isSiteAdmin) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Admin', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: _tile(
              context,
              icon: Icons.admin_panel_settings_rounded,
              title: 'Admin tools',
              subtitle: 'Web filtering, app updates & data',
              screen: const AdminToolsScreen(),
            ),
          ),
        ],
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
          child: Text('Maryada · v1.0.0',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
    Color iconColor = AppColors.primary,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
    );
  }
}
