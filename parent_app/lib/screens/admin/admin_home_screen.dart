import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_update_repository.dart';
import '../../data/hosts_repository.dart';
import '../../data/family_repository.dart';
import '../../data/invites_repository.dart';
import '../../models/app_user.dart';
import '../../models/family.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/profile_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../widgets/typed_danger_dialog.dart';
import '../../data/retention_service.dart';
import '../publish_update/publish_update_screen.dart';
import 'clear_data_screen.dart';
import 'content_keywords_screen.dart';
import 'family_tags_screen.dart';
import 'host_detail_screen.dart';
import 'web_policy_screen.dart';

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
      floatingActionButton: null,
      // The console is a menu: each section opens its own page, so the landing
      // stays short however many parents there are.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
              children: [
                Center(child: const BrandMark(size: 64)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Site administration',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Grant access to parents and manage what every device enforces.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _SectionCard(
                  icon: Icons.people_alt_rounded,
                  title: 'Parents & families',
                  subtitle: 'Grant access, manage households, delete empty ones',
                  screen: _PeopleScreen(),
                ),
                const SizedBox(height: AppSpacing.sm),
                const _SectionCard(
                  icon: Icons.admin_panel_settings_rounded,
                  title: 'Admin tools',
                  subtitle: 'Web filtering, app updates & activity data',
                  iconColor: AppColors.info,
                  screen: _AdminToolsPage(),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Made with ❤️ by ISKCON Brahmapur',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the console: a heading that opens its own page.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: Text(subtitle),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}

/// Parents and their households on one page: who has access, and which
/// families exist. Granting access works from either tab.
class _PeopleScreen extends StatelessWidget {
  const _PeopleScreen();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parents & families'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Parents'),
              Tab(text: 'Families'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _inviteHost(context),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Grant access'),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
                  AppSpacing.md, AppSpacing.xxl * 2),
              children: const [_HostsList()],
            ),
            const _FamiliesList(),
          ],
        ),
      ),
    );
  }
}

/// Every household, with what's attached to it. Only an empty family (no child
/// profiles, no registered devices) can be deleted.
class _FamiliesList extends StatefulWidget {
  const _FamiliesList();

  @override
  State<_FamiliesList> createState() => _FamiliesListState();
}

class _FamiliesListState extends State<_FamiliesList> {
  late final Stream<List<FamilyModel>> _stream =
      FamilyRepository.instance.watchAllFamilies();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FamilyModel>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final families = snap.data ?? const <FamilyModel>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
              AppSpacing.md, AppSpacing.xxl * 2),
          children: [
            if (families.isEmpty)
              const _EmptyCard(
                icon: Icons.home_work_rounded,
                title: 'No families yet',
                subtitle: 'A family is created when you grant a parent access.',
              )
            else
              for (final f in families) ...[
                _FamilyAdminCard(key: ValueKey(f.id), family: f),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        );
      },
    );
  }
}

class _FamilyAdminCard extends StatefulWidget {
  const _FamilyAdminCard({super.key, required this.family});
  final FamilyModel family;

  @override
  State<_FamilyAdminCard> createState() => _FamilyAdminCardState();
}

class _FamilyAdminCardState extends State<_FamilyAdminCard> {
  late Future<({int children, int devices})> _load =
      FamilyRepository.instance.familyLoad(widget.family.id);

  String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.family.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename family'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Family name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            label: 'Save',
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == widget.family.name) {
      return;
    }
    if (!mounted) return;
    await _save(
      context,
      () => FamilyRepository.instance.renameFamily(widget.family.id, newName),
      'Couldn\'t rename',
      'Family renamed to "$newName".',
    );
  }

  Future<void> _delete() async {
    final load = await _load;
    if (!mounted) return;
    if (load.children > 0 || load.devices > 0) {
      final holding = [
        if (load.children > 0) _plural(load.children, 'child profile', 'child profiles'),
        if (load.devices > 0) _plural(load.devices, 'registered device', 'registered devices'),
      ].join(' and ');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
              'Can\'t delete "${widget.family.name}" — it still has $holding. '
              'Remove them first.'),
        ));
      return;
    }
    if (await _confirm(context,
        title: 'Delete family?',
        message:
            '"${widget.family.name}" has no children or devices. Parents whose '
            'access names this family will show "no family assigned" until you '
            'grant them another.',
        confirmLabel: 'Delete',
        destructive: true)) {
      if (!mounted) return;
      await _save(
        context,
        () => FamilyRepository.instance.deleteFamily(widget.family.id),
        'Couldn\'t delete',
        '"${widget.family.name}" was deleted.',
      );
      // The guard may have refused because something was attached meanwhile.
      if (mounted) {
        setState(() =>
            _load = FamilyRepository.instance.familyLoad(widget.family.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.family;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.accent.withValues(alpha: 0.14),
              child: const Icon(Icons.home_work_rounded,
                  color: AppColors.accentDark),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name.isEmpty ? '(unnamed)' : f.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  FutureBuilder<({int children, int devices})>(
                    future: _load,
                    builder: (context, snap) {
                      final parents =
                          _plural(f.parentUids.length, 'parent', 'parents');
                      final rest = snap.hasData
                          ? ' · ${_plural(snap.data!.children, 'child', 'children')}'
                              ' · ${_plural(snap.data!.devices, 'device', 'devices')}'
                          : ' · …';
                      return Text(
                        '$parents$rest',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Tags',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FamilyTagsScreen(
                    familyId: f.id,
                    familyName: f.name.isEmpty ? 'Family' : f.name,
                  ),
                ),
              ),
              icon: const Icon(Icons.sell_outlined),
            ),
            IconButton(
              tooltip: 'Rename family',
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete family',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

/// The site admin's tools, on the console itself rather than buried in the
/// profile menu.
class _AdminToolsPage extends StatelessWidget {
  const _AdminToolsPage();

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
                  title: 'Browser & filtering',
                  subtitle: 'Categories, browsers, incognito',
                  screen: const WebPolicyScreen(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('App updates', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                _tile(
                  context,
                  icon: Icons.system_update_rounded,
                  title: 'Publish child update',
                  subtitle: 'Push a new child app version over the air',
                  screen: const PublishUpdateScreen(),
                ),
                const Divider(height: 1, indent: 56),
                _tile(
                  context,
                  icon: Icons.desktop_windows_rounded,
                  iconColor: const Color(0xFF0078D4),
                  title: 'Publish PC update',
                  subtitle: 'Push a new Windows agent build to child PCs',
                  screen: const PublishUpdateScreen(
                      target: AppUpdateRepository.windowsDoc),
                ),
                const Divider(height: 1, indent: 56),
                _tile(
                  context,
                  icon: Icons.phone_android_rounded,
                  iconColor: AppColors.info,
                  title: 'Publish parent update',
                  subtitle: 'Offer a new Maryada Host build to parents',
                  screen: const PublishUpdateScreen(
                      target: AppUpdateRepository.parentDoc),
                ),
              ],
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
              title: 'Activity data',
              subtitle: 'Auto-delete window & clear history',
              screen: const ClearDataScreen(),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _inviteHost(BuildContext context) async {
    final emailCtl = TextEditingController();
    final limitCtl = TextEditingController(text: '5');
    final familyNameCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    // Nothing preselected: view-only is as valid a grant as edit, including for
    // the first parent of a family, so the choice is always made deliberately.
    AccessLevel? access;
    var accessMissing = false;
    // Empty = create a new household, named below.
    var familyId = '';
    var families = <FamilyModel>[];
    try {
      families = await FamilyRepository.instance.listFamilies();
    } catch (_) {
      // Non-fatal: the picker just won't offer existing households.
    }
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Grant parent access'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                    // No '/': the grant is stored under this address.
                    if (s.isEmpty ||
                        s.contains('/') ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Family', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: familyId,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Create a new family…'),
                    ),
                    for (final f in families)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text(f.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => familyId = v ?? ''),
                ),
                if (familyId.isEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: familyNameCtl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Family name',
                      hintText: 'e.g. Sharma family',
                      isDense: true,
                    ),
                    validator: (v) {
                      if (familyId.isNotEmpty) return null;
                      final s = (v ?? '').trim();
                      if (s.length < 2) return 'Name this family';
                      // Names are how the admin tells households apart, so two
                      // families may not share one.
                      final taken = families.any((f) =>
                          f.name.trim().toLowerCase() == s.toLowerCase());
                      return taken ? 'That name is already used' : null;
                    },
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  familyId.isEmpty
                      ? 'A new household — they see only its children.'
                      : 'They join this family and share its children.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Access',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<AccessLevel>(
                  emptySelectionAllowed: true,
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
                  selected: {if (access != null) access!},
                  onSelectionChanged: (s) => setLocal(() {
                    access = s.isEmpty ? null : s.first;
                    accessMissing = false;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (access) {
                    AccessLevel.view =>
                      'Can view families, children and rules only.',
                    AccessLevel.edit => 'Can add children and change rules.',
                    null => accessMissing
                        ? 'Choose view or edit access.'
                        : 'Choose how much this parent can do.',
                  },
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: accessMissing && access == null
                            ? Theme.of(ctx).colorScheme.error
                            : null,
                      ),
                ),
                if (access == AccessLevel.edit) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: limitCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Device limit',
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
          ),
          actions: [
            DialogCancelButton(onPressed: () => Navigator.pop(ctx, false)),
            DialogConfirmButton(
              onPressed: () {
                final formOk = formKey.currentState?.validate() ?? false;
                if (access == null) setLocal(() => accessMissing = true);
                if (formOk && access != null) {
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
      // A new household is created here, so the grant always names one and the
      // parent never has to invent a family for themselves.
      final targetFamilyId = familyId.isNotEmpty
          ? familyId
          : (await FamilyRepository.instance
                  .createFamilyForGrant(familyNameCtl.text))
              .id;
      await InvitesRepository.instance.createInvite(
        email: emailCtl.text,
        maxChildren: int.parse(limitCtl.text.trim()),
        access: access!,
        familyId: targetFamilyId,
      );
      if (context.mounted) {
        _showGrantDone(context, emailCtl.text.trim(), access!);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Couldn’t grant access — ${friendlyError(e)}')));
      }
    }
}

void _showGrantDone(BuildContext context, String email, AccessLevel access) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Access granted'),
        content: Text(
          'Ask $email to open Maryada and continue with Google using that '
          'address. They get '
          '${access == AccessLevel.view ? 'view only' : 'edit'} access on '
          'sign-in — there is no code to enter.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
}

class _HostsList extends StatefulWidget {
  const _HostsList();

  @override
  State<_HostsList> createState() => _HostsListState();
}

class _HostsListState extends State<_HostsList> {
  // Built once. Creating the stream inside build() re-subscribed on every
  // rebuild, so a change saved here only showed after leaving and reopening
  // the page.
  late final Stream<List<AppUser>> _stream =
      HostsRepository.instance.watchHosts();
  late final Stream<List<Invite>> _grants = InvitesRepository.instance.watch();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final hosts = snap.data ?? const <AppUser>[];
        // A granted parent has no account until they first sign in, so the
        // grant itself is listed until then — otherwise granting access looked
        // like it did nothing.
        return StreamBuilder<List<Invite>>(
          stream: _grants,
          builder: (context, grantSnap) {
            final emails = hosts.map((h) => h.email.toLowerCase()).toSet();
            final pending = (grantSnap.data ?? const <Invite>[])
                .where((i) => !i.used && !emails.contains(i.email.toLowerCase()))
                .toList();
            if (hosts.isEmpty && pending.isEmpty) {
              return const _EmptyCard(
                icon: Icons.groups_2_rounded,
                title: 'No parents yet',
                subtitle: 'Grant access to a parent to get started.',
              );
            }
            return Column(
              children: [
                for (final i in pending) ...[
                  _PendingGrantCard(grant: i),
                  const SizedBox(height: AppSpacing.sm),
                ],
                for (final h in hosts) ...[
                  _HostCard(host: h),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// A grant the parent hasn't signed in against yet.
class _PendingGrantCard extends StatelessWidget {
  const _PendingGrantCard({required this.grant});
  final Invite grant;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.warning.withValues(alpha: 0.12),
              child: const Icon(Icons.mark_email_unread_rounded,
                  color: AppColors.warning),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(grant.email,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Waiting for first sign-in · '
                    '${grant.access == AccessLevel.edit ? 'Edit access' : 'View only'}',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v != 'revoke') return;
                if (await _confirm(context,
                    title: 'Revoke grant?',
                    message:
                        '${grant.email} will no longer get access when they sign in.',
                    confirmLabel: 'Revoke',
                    destructive: true)) {
                  if (!context.mounted) return;
                  await _save(
                    context,
                    () => InvitesRepository.instance.delete(grant.code),
                    'Couldn’t revoke',
                    'The grant for ${grant.email} was revoked.',
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'revoke',
                  child: Text('Revoke grant',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
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
                      if (!context.mounted) return;
                      await _save(
                        context,
                        () => HostsRepository.instance
                            .setAccess(host.uid, AccessLevel.edit),
                        'Couldn’t change access',
                        '${host.email} now has edit access.',
                      );
                    }
                  } else if (v == 'view') {
                    if (await _confirm(context,
                        title: 'Set to view only?',
                        message:
                            '${host.email} will only be able to view — not add children or change rules.',
                        confirmLabel: 'Set view only')) {
                      if (!context.mounted) return;
                      await _save(
                        context,
                        () => HostsRepository.instance
                            .setAccess(host.uid, AccessLevel.view),
                        'Couldn’t change access',
                        '${host.email} is now view only.',
                      );
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
                      if (!context.mounted) return;
                      await _save(
                        context,
                        () => HostsRepository.instance
                            .setSuspended(host.uid, suspend),
                        suspend ? 'Couldn’t suspend' : 'Couldn’t activate',
                        suspend
                            ? '${host.email} is suspended.'
                            : '${host.email} can sign in again.',
                      );
                    }
                  } else if (v == 'remove') {
                    // Same bar as the detail screen: removal only happens
                    // after the admin types the parent's email.
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => TypedDangerDialog(
                        title: 'Remove this parent?',
                        warning:
                            'This removes ${host.email}’s access. They’ll be '
                            'blocked until you grant access again. Their '
                            'families and profiles are not deleted.',
                        prompt: 'Type their email address to confirm:',
                        expected: host.email,
                        actionLabel: 'Remove',
                      ),
                    );
                    if (confirmed == true) {
                      if (!context.mounted) return;
                      await _save(
                        context,
                        () => HostsRepository.instance.delete(host.uid),
                        'Couldn’t remove',
                        '${host.email} was removed.',
                      );
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
                        value: 'limit', child: Text('Set device limit')),
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
      if (!context.mounted) return;
      await _save(
        context,
        () => HostsRepository.instance.setMaxChildren(host.uid, n),
        'Couldn’t set the device limit',
        'Device limit set to $n.',
      );
    }
  }
}

/// Reports an admin write instantly and corrects afterwards if it failed.
/// Firestore applies the change locally before the server acknowledges, so the
/// list updates immediately — waiting behind a modal made every tap feel slow.
Future<void> _save(
  BuildContext context,
  Future<void> Function() action,
  String failure,
  String success,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(success)));
  try {
    await action();
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('$failure — ${friendlyError(e)}'),
      ));
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
