import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/hosts_repository.dart';
import '../../data/invites_repository.dart';
import '../../models/app_user.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/profile_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../data/retention_service.dart';
import 'host_detail_screen.dart';

/// The admin console: manage host (parent) accounts and their child limits, and
/// invite new hosts. Only reachable when the signed-in account has the `admin`
/// role.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  @override
  void initState() {
    super.initState();
    // The retention purge has no server to run on, so it happens here whenever
    // the admin opens the console (it no-ops unless a day has passed).
    RetentionService.runIfDue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 28, showGlow: false),
            const SizedBox(width: AppSpacing.sm),
            Text('Site admin',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
          ],
        ),
        actions: const [
          ThemeToggleButton(),
          ProfileButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _inviteHost(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Grant access'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl * 2),
        children: [
          Text('Parents',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const _HostsList(),
          const SizedBox(height: AppSpacing.lg),
          Text('Pending access grants',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const _InvitesList(),
        ],
      ),
    );
  }

  Future<void> _inviteHost(BuildContext context) async {
    final emailCtl = TextEditingController();
    final limitCtl = TextEditingController(text: '5');
    final formKey = GlobalKey<FormState>();
    var access = AccessLevel.edit;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Grant parent access'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Parent email',
                    hintText: 'parent@example.com',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty || !s.contains('@') || !s.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Access',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<AccessLevel>(
                  segments: const [
                    ButtonSegment(
                      value: AccessLevel.view,
                      label: Text('View'),
                      icon: Icon(Icons.visibility_outlined),
                    ),
                    ButtonSegment(
                      value: AccessLevel.edit,
                      label: Text('Edit'),
                      icon: Icon(Icons.edit_outlined),
                    ),
                  ],
                  selected: {access},
                  onSelectionChanged: (s) => setLocal(() => access = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  access == AccessLevel.view
                      ? 'Can view families, children and rules only.'
                      : 'Can add children and change rules.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                if (access == AccessLevel.edit) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: limitCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Child limit',
                      hintText: '5',
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1 || n > 100) return '1 – 100';
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            DialogCancelButton(onPressed: () => Navigator.pop(ctx, false)),
            DialogConfirmButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              label: 'Grant access',
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final code = await InvitesRepository.instance.createInvite(
        email: emailCtl.text,
        maxChildren: int.parse(limitCtl.text.trim()),
        access: access,
      );
      if (context.mounted) {
        _showInviteCode(context, emailCtl.text.trim(), code, access);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Couldn’t grant access — ${friendlyError(e)}')));
      }
    }
  }

  void _showInviteCode(
      BuildContext context, String email, String code, AccessLevel access) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Access granted'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ask $email to sign in with this email (Google or password). '
                'Their account becomes an org admin with '
                '${access == AccessLevel.view ? 'view' : 'edit'} access on first '
                'sign-in.'),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Access code copied')));
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _HostsList extends StatelessWidget {
  const _HostsList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: HostsRepository.instance.watchHosts(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final hosts = snap.data ?? const <AppUser>[];
        if (hosts.isEmpty) {
          return const _EmptyCard(
            icon: Icons.groups_2_rounded,
            title: 'No hosts yet',
            subtitle: 'Invite a parent to create the first host account.',
          );
        }
        return Column(
          children: [
            for (final h in hosts) ...[
              _HostCard(host: h),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host});
  final AppUser host;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HostDetailScreen(host: host)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: (host.suspended
                        ? AppColors.danger
                        : AppColors.primary)
                    .withValues(alpha: 0.12),
                child: Icon(Icons.person_rounded,
                    color:
                        host.suspended ? AppColors.danger : AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.email,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      host.suspended
                          ? 'Suspended · ${host.access == AccessLevel.edit ? 'Edit' : 'View'} · limit ${host.maxChildren}'
                          : '${host.access == AccessLevel.edit ? 'Edit access' : 'View only'} · limit ${host.maxChildren}',
                      style: TextStyle(
                        color: host.suspended
                            ? AppColors.danger
                            : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'limit') {
                    await _editLimit(context, host);
                  } else if (v == 'edit') {
                    if (await _confirm(context,
                        title: 'Give edit access?',
                        message:
                            '${host.email} will be able to add children and change rules.',
                        confirmLabel: 'Give edit access')) {
                      await HostsRepository.instance
                          .setAccess(host.uid, AccessLevel.edit);
                    }
                  } else if (v == 'view') {
                    if (await _confirm(context,
                        title: 'Set to view only?',
                        message:
                            '${host.email} will only be able to view — not add children or change rules.',
                        confirmLabel: 'Set view only')) {
                      await HostsRepository.instance
                          .setAccess(host.uid, AccessLevel.view);
                    }
                  } else if (v == 'suspend') {
                    final suspend = !host.suspended;
                    if (await _confirm(context,
                        title: suspend ? 'Suspend parent?' : 'Activate parent?',
                        message: suspend
                            ? '${host.email} will be blocked from signing in.'
                            : '${host.email} will be able to sign in again.',
                        confirmLabel: suspend ? 'Suspend' : 'Activate',
                        destructive: suspend)) {
                      await HostsRepository.instance
                          .setSuspended(host.uid, suspend);
                    }
                  } else if (v == 'remove') {
                    if (await _confirm(context,
                        title: 'Remove parent?',
                        message:
                            'This removes ${host.email}’s access. They’ll be blocked until granted again. Families and children are not deleted.',
                        confirmLabel: 'Remove',
                        destructive: true)) {
                      await HostsRepository.instance.delete(host.uid);
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (host.access != AccessLevel.edit)
                    const PopupMenuItem(
                        value: 'edit', child: Text('Give edit access')),
                  if (host.access != AccessLevel.view)
                    const PopupMenuItem(
                        value: 'view', child: Text('Set to view only')),
                  if (host.access == AccessLevel.edit)
                    const PopupMenuItem(
                        value: 'limit', child: Text('Set child limit')),
                  PopupMenuItem(
                    value: 'suspend',
                    child: Text(host.suspended ? 'Activate' : 'Suspend'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove parent',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editLimit(BuildContext context, AppUser host) async {
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

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx, false)),
          if (destructive)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            )
          else
            DialogConfirmButton(
              onPressed: () => Navigator.pop(ctx, true),
              label: confirmLabel,
            ),
        ],
      ),
    );
    return ok == true;
  }
}

class _InvitesList extends StatelessWidget {
  const _InvitesList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Invite>>(
      stream: InvitesRepository.instance.watch(),
      builder: (context, snap) {
        final invites =
            (snap.data ?? const <Invite>[]).where((i) => !i.used).toList();
        if (invites.isEmpty) {
          return const _EmptyCard(
            icon: Icons.mark_email_unread_rounded,
            title: 'No pending invites',
            subtitle: 'Invites you create appear here until redeemed.',
          );
        }
        return Column(
          children: [
            for (final i in invites) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: Text(i.email,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      'Code ${i.code} · ${i.access == AccessLevel.edit ? 'Edit' : 'View'} · limit ${i.maxChildren}'),
                  trailing: IconButton(
                    tooltip: 'Cancel invite',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () =>
                        InvitesRepository.instance.delete(i.code),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }
}
