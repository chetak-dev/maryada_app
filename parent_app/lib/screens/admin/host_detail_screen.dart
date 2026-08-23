import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/family_repository.dart';
import '../../data/hosts_repository.dart';
import '../../models/app_user.dart';
import '../../models/child.dart';
import '../../models/family.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/typed_danger_dialog.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/status_pill.dart';

/// Admin view of a single parent (org admin): their access, child limit and
/// status controls, plus the families and children they manage.
class HostDetailScreen extends StatelessWidget {
  const HostDetailScreen({super.key, required this.host});

  final AppUser host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Parent')),
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
                  leading: const Icon(Icons.shield_outlined,
                      color: AppColors.primary),
                  title: const Text('Access',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(host.access == AccessLevel.edit
                      ? 'Edit — can add children & change rules'
                      : 'View only — read-only'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
                  onTap: () => _editAccess(context),
                ),
                if (host.access == AccessLevel.edit) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    leading: const Icon(Icons.tune_rounded,
                        color: AppColors.primary),
                    title: const Text('Device limit',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Currently ${host.maxChildren} paired device(s)'),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted),
                    onTap: () => _editLimit(context),
                  ),
                ],
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
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.person_remove_rounded,
                color: AppColors.danger),
            label: const Text('Remove parent',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TypedDangerDialog(
        title: 'Remove this parent?',
        warning:
            'This removes ${host.email}’s access. They’ll be blocked until '
            'you grant access again. Their families and profiles are not '
            'deleted.',
        prompt: 'Type their email address to confirm:',
        expected: host.email,
        actionLabel: 'Remove',
      ),
    );
    if (confirmed != true) return;
    try {
      await HostsRepository.instance.delete(host.uid);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn’t remove — ${friendlyError(e)}')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('${host.email} was removed.')),
    );
    navigator.pop();
  }

  Future<void> _editAccess(BuildContext context) async {
    final choice = await showDialog<AccessLevel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set access'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AccessLevel.edit),
            child: const ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
              subtitle: Text('Add children and change rules'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, AccessLevel.view),
            child: const ListTile(
              leading: Icon(Icons.visibility_outlined),
              title: Text('View only'),
              subtitle: Text('Read-only access'),
            ),
          ),
        ],
      ),
    );
    if (choice != null) {
      await HostsRepository.instance.setAccess(host.uid, choice);
    }
  }

  Future<void> _editLimit(BuildContext context) async {
    final ctl = TextEditingController(text: '${host.maxChildren}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device limit'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Max paired devices'),
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v != null && v >= 1 && v <= 100) Navigator.pop(ctx, v);
            },
            label: 'Save',
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
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: Text('This parent has no family yet.',
                    style: TextStyle(
                        color: AppColors.textSecondaryOf(context))),
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
