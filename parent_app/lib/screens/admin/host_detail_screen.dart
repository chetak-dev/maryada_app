import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/family_repository.dart';
import '../../data/hosts_repository.dart';
import '../../models/app_user.dart';
import '../../models/child.dart';
import '../../models/family.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_pill.dart';

/// Admin read-only view of a single host: their child limit / status controls
/// plus the families and children they manage.
class HostDetailScreen extends StatelessWidget {
  const HostDetailScreen({super.key, required this.host});

  final AppUser host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Host')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          _HostHeader(host: host),
          const SizedBox(height: AppSpacing.lg),
          Text('Controls', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  leading: const Icon(Icons.tune_rounded,
                      color: AppColors.primary),
                  title: const Text('Child limit',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Currently ${host.maxChildren}'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
                  onTap: () => _editLimit(context),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  secondary: Icon(Icons.block_rounded,
                      color: host.suspended
                          ? AppColors.danger
                          : AppColors.textMuted),
                  title: const Text('Suspended',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Blocks this host from signing in'),
                  value: host.suspended,
                  onChanged: (v) =>
                      HostsRepository.instance.setSuspended(host.uid, v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Families & children', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _Families(hostUid: host.uid),
        ],
      ),
    );
  }

  Future<void> _editLimit(BuildContext context) async {
    final ctl = TextEditingController(text: '${host.maxChildren}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Child limit'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Max children'),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v != null && v >= 1 && v <= 100) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (n != null) {
      await HostsRepository.instance.setMaxChildren(host.uid, n);
    }
  }
}

class _HostHeader extends StatelessWidget {
  const _HostHeader({required this.host});
  final AppUser host;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.raised,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: const Icon(Icons.person_rounded, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(host.email,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        )),
                const SizedBox(height: 4),
                StatusPill(
                  label: host.suspended ? 'Suspended' : 'Active',
                  color: host.suspended ? AppColors.danger : AppColors.success,
                  icon: host.suspended
                      ? Icons.lock_outline_rounded
                      : Icons.verified_user_rounded,
                  onDark: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Families extends StatelessWidget {
  const _Families({required this.hostUid});
  final String hostUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FamilyModel>>(
      stream: FamilyRepository.instance.watchFamilies(hostUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final families = snap.data ?? const <FamilyModel>[];
        if (families.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: Text('This host has no family yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final f in families) ...[
              _FamilyCard(family: f),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family});
  final FamilyModel family;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(family.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            StreamBuilder<List<Child>>(
              stream: FamilyRepository.instance.watchChildren(family.id),
              builder: (context, snap) {
                final kids = snap.data ?? const <Child>[];
                if (kids.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(left: 28, top: 2, bottom: 2),
                    child: Text('No children linked.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                  );
                }
                return Column(
                  children: [
                    for (final c in kids)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: c.avatarColor,
                              child: Text(c.initials,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(c.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            StatusPill(
                              label: c.effectiveStatus.label,
                              color: c.effectiveStatus.color,
                              icon: c.effectiveStatus.icon,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
