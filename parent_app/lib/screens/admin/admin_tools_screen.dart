import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../publish_update/publish_update_screen.dart';
import 'clear_data_screen.dart';
import 'content_keywords_screen.dart';
import 'web_policy_screen.dart';

/// Site-admin tools grouped in one place (reached from the profile): web
/// filtering, child-app updates and data clearing.
class AdminToolsScreen extends StatelessWidget {
  const AdminToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          Text('Web filtering', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                _tile(
                  context,
                  icon: Icons.text_fields_rounded,
                  title: 'Content keywords',
                  subtitle: 'Blocked words per category',
                  screen: const ContentKeywordsScreen(),
                ),
                const Divider(height: 1, indent: 56),
                _tile(
                  context,
                  icon: Icons.shield_rounded,
                  title: 'Browser & safe browsing',
                  subtitle: 'Categories, browsers, incognito, safe browsing',
                  screen: const WebPolicyScreen(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Child app', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: _tile(
              context,
              icon: Icons.system_update_rounded,
              title: 'Publish app update',
              subtitle: 'Push a new child app version over the air',
              screen: const PublishUpdateScreen(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Data', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: _tile(
              context,
              icon: Icons.delete_sweep_rounded,
              iconColor: AppColors.danger,
              title: 'Clear activity data',
              subtitle: 'Wipe history for children — devices stay paired',
              screen: const ClearDataScreen(),
            ),
          ),
        ],
      ),
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
