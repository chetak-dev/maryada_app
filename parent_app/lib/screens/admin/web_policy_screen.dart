import 'package:flutter/material.dart';

import '../../data/site_policy_repository.dart';
import '../../models/web_filter.dart';
import '../../theme/tokens.dart';

/// Site-admin editor for the global browser / safe-browsing policy. These apply
/// to every child device and cannot be changed by org admins.
class WebPolicyScreen extends StatelessWidget {
  const WebPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browser & safe browsing')),
      body: StreamBuilder<WebPolicy>(
        stream: SitePolicyRepository.instance.watchPolicy(),
        builder: (context, snap) {
          final p = snap.data ?? const WebPolicy();
          final categories = demoCategories();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
            children: [
              Card(
                child: Column(
                  children: [
                    // Not a switch: the filter is the reason the app exists, so
                    // there is deliberately no way to turn it off — not even
                    // here.
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      leading: _icon(Icons.shield_rounded, AppColors.success),
                      title: const Text('Safe browsing',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                          'Always on for every device. Unsafe sites are blocked '
                          'and cannot be unblocked by anyone.'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text(
                          'ALWAYS ON',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      secondary: _icon(Icons.public_off_rounded,
                          AppColors.primary),
                      title: const Text('Block other browsers',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                          'Only Chrome is allowed; other browsers (and their '
                          'private modes) are blocked.'),
                      value: p.blockOtherBrowsers,
                      onChanged: (v) => SitePolicyRepository.instance
                          .setPolicy(blockOtherBrowsers: v),
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      secondary:
                          _icon(Icons.visibility_off_rounded, AppColors.warning),
                      title: const Text('Allow incognito mode',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                          'When off, incognito / private browsing is disabled in '
                          'Chrome so the filter can’t be bypassed.'),
                      value: p.allowIncognito,
                      onChanged: (v) => SitePolicyRepository.instance
                          .setPolicy(allowIncognito: v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Blocked categories',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < categories.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        secondary: _catIcon(categories[i]),
                        title: Text(categories[i].name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(categories[i].description),
                        value: p.blockedCategories.contains(categories[i].id),
                        onChanged: (v) {
                          final next = {...p.blockedCategories};
                          if (v) {
                            next.add(categories[i].id);
                          } else {
                            next.remove(categories[i].id);
                          }
                          SitePolicyRepository.instance
                              .setPolicy(blockedCategories: next);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  'These apply to every child device. Org admins cannot disable '
                  'safe browsing, change these browser controls, or turn any '
                  'category off — they can only add their own custom blocked '
                  'sites.',
                  style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _icon(IconData icon, Color color) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: color),
      );

  Widget _catIcon(WebCategory c) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(c.icon, color: c.color),
      );
}
