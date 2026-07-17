import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/hosts_repository.dart';
import '../../data/invites_repository.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';
import 'host_detail_screen.dart';

/// The admin console: manage host (parent) accounts and their child limits, and
/// invite new hosts. Only reachable when the signed-in account has the `admin`
/// role.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    if (AuthService.instance.isConfigured) {
      await AuthService.instance.signOut();
    } else if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
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
            Text('Admin console',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _signOut(context),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _inviteHost(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Invite host'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl * 2),
        children: [
          Text('Hosts',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const _HostsList(),
          const SizedBox(height: AppSpacing.lg),
          Text('Pending invites',
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite a host'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailCtl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Host email',
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
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Create invite'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final code = await InvitesRepository.instance.createInvite(
        email: emailCtl.text,
        maxChildren: int.parse(limitCtl.text.trim()),
      );
      if (context.mounted) _showInviteCode(context, emailCtl.text.trim(), code);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Couldn\u2019t invite: $e')));
      }
    }
  }

  void _showInviteCode(BuildContext context, String email, String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ask $email to sign up with this email. Their account becomes '
                'a host automatically on first sign-in.'),
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
                  const SnackBar(content: Text('Invite code copied')));
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
                          ? 'Suspended · limit ${host.maxChildren}'
                          : 'Child limit: ${host.maxChildren}',
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
                  } else if (v == 'suspend') {
                    await HostsRepository.instance
                        .setSuspended(host.uid, !host.suspended);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'limit', child: Text('Set child limit')),
                  PopupMenuItem(
                    value: 'suspend',
                    child: Text(host.suspended ? 'Activate' : 'Suspend'),
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
                  subtitle: Text('Code ${i.code} · limit ${i.maxChildren}'),
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
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
