import 'package:flutter/material.dart';

import '../../data/site_policy_repository.dart';
import '../../theme/tokens.dart';

/// Site-admin editor for the global browser / safe-browsing policy. These apply
/// to every child device and cannot be changed by org admins. The protective
/// content categories are always on and deliberately not listed here.
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
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  'These apply to every child device. Unsafe content categories '
                  '(adult, gambling, drugs, weapons, violence) are always '
                  'blocked and are not configurable — the words they block on '
                  'are listed under Content keywords.',
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
}
