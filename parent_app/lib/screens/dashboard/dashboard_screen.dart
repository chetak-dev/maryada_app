import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/rules_repository.dart';
import '../../data/user_repository.dart';
import '../../data/web_filter_repository.dart';
import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/child.dart';
import '../../models/family.dart';
import '../../models/screen_time_rule.dart';
import '../../theme/tokens.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/theme_toggle_button.dart';
import '../add_child/add_child_screen.dart';
import '../app_rules/app_rules_screen.dart';
import '../child_detail/child_detail_screen.dart';
import '../screen_time/screen_time_screen.dart';
import '../web_filter/web_filter_screen.dart';

/// The guardian home: family devices at a glance + family-wide controls.
/// Uses live Firestore data when connected ([uid] set + [Db.ready]); otherwise
/// shows demo data so the UI is fully usable without a backend.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.uid});

  final String? uid;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Bumped by the sync button to re-subscribe the live streams (forces a fresh
  // read from the server when the linked state looks stale/offline).
  int _sync = 0;

  bool get _live => widget.uid != null && Db.ready;

  void _resync() {
    setState(() => _sync++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Syncing with linked devices…'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: const BrandLockup(markSize: 32),
        actions: const [ThemeToggleButton(), SizedBox(width: AppSpacing.xs)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
        children: [
          const _DashboardHero(),
          const SizedBox(height: AppSpacing.lg),
          _WebFilterAlertBanner(uid: _live ? uid : null),
          _FamilyControls(key: ValueKey('controls_$_sync'), uid: _live ? uid : null),
          const SizedBox(height: AppSpacing.lg),
          _FamilyChildren(
            key: ValueKey('children_$_sync'),
            uid: _live ? uid : null,
            onSync: _resync,
          ),
        ],
      ),
    );
  }
}

/// A warm gradient greeting hero that anchors the "Royal & Warm" identity at
/// the top of the home tab.
class _DashboardHero extends StatelessWidget {
  const _DashboardHero();

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.raised,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your family, at a glance',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.shield_moon_rounded,
                color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

/// A prominent warning shown on the home screen whenever the family's web
/// filter is turned off, so the parent notices no sites are being blocked.
class _WebFilterAlertBanner extends StatelessWidget {
  const _WebFilterAlertBanner({required this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null || !Db.ready) return const SizedBox.shrink();
    return StreamBuilder<List<FamilyModel>>(
      stream: FamilyRepository.instance.watchFamilies(uid!),
      builder: (context, famSnap) {
        final fams = famSnap.data ?? const <FamilyModel>[];
        if (fams.isEmpty) return const SizedBox.shrink();
        final familyId = fams.first.id;
        return StreamBuilder<WebFilterSettings>(
          stream: WebFilterRepository.instance.watch(familyId),
          builder: (context, snap) {
            final off = snap.hasData && !snap.data!.enabled;
            if (!off) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WebFilterScreen(familyId: familyId),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: const Icon(Icons.gpp_bad_rounded,
                              color: AppColors.danger, size: 22),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Web filter is off',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.danger)),
                              SizedBox(height: 2),
                              Text(
                                'No websites are blocked for your child. Tap to turn on.',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.danger),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The Screen-time control tile, which shows a live red badge on the home
/// screen whenever the device is paused or bedtime is on.
class _ScreenTimeControlTile extends StatelessWidget {
  const _ScreenTimeControlTile({required this.familyId});
  final String? familyId;

  static bool _bedtimeActiveNow(ScreenTimeRule r) {
    final now = TimeOfDay.now();
    final mins = now.hour * 60 + now.minute;
    final start = r.bedtimeStart;
    final end = r.bedtimeEnd;
    return start <= end
        ? (mins >= start && mins < end)
        : (mins >= start || mins < end); // window wraps past midnight
  }

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScreenTimeScreen(familyId: familyId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (familyId == null) {
      return _ControlTile(
        icon: Icons.timelapse_rounded,
        color: AppColors.primary,
        title: 'Screen time & schedules',
        subtitle: 'Bedtime, downtime, pause now',
        onTap: () => _open(context),
      );
    }
    return StreamBuilder<ScreenTimeRule>(
      stream: RulesRepository.instance.watchScreenTime(familyId!),
      builder: (context, snap) {
        final rule = snap.data;
        String? badge;
        if (rule != null) {
          if (rule.paused) {
            badge = 'PAUSED';
          } else if (rule.bedtimeEnabled) {
            badge = _bedtimeActiveNow(rule) ? 'BEDTIME' : 'BEDTIME ON';
          }
        }
        return _ControlTile(
          icon: Icons.timelapse_rounded,
          color: AppColors.primary,
          title: 'Screen time & schedules',
          subtitle: 'Bedtime, downtime, pause now',
          badge: badge,
          onTap: () => _open(context),
        );
      },
    );
  }
}

/// The Web-filter control tile, showing a live green "ON" badge on the home
/// screen when safe browsing is enabled.
class _WebFilterControlTile extends StatelessWidget {
  const _WebFilterControlTile({required this.familyId});
  final String? familyId;

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebFilterScreen(familyId: familyId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (familyId == null) {
      return _ControlTile(
        icon: Icons.public_rounded,
        color: AppColors.success,
        title: 'Web filter',
        subtitle: 'Safe browsing, block sites',
        onTap: () => _open(context),
      );
    }
    return StreamBuilder<WebFilterSettings>(
      stream: WebFilterRepository.instance.watch(familyId!),
      builder: (context, snap) {
        final on = snap.data?.enabled ?? false;
        return _ControlTile(
          icon: Icons.public_rounded,
          color: AppColors.success,
          title: 'Web filter',
          subtitle: 'Safe browsing, block sites',
          badge: on ? 'ON' : null,
          badgeColor: AppColors.success,
          onTap: () => _open(context),
        );
      },
    );
  }
}

/// Family-wide control tiles. Supplies the live familyId (when connected) so
/// editors can persist; opens in demo mode otherwise.
class _FamilyControls extends StatelessWidget {
  const _FamilyControls({super.key, required this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const _ControlsCard(familyId: null);
    return StreamBuilder<List<FamilyModel>>(
      stream: FamilyRepository.instance.watchFamilies(uid!),
      builder: (context, snap) {
        final fams = snap.data ?? const <FamilyModel>[];
        final familyId = fams.isEmpty ? null : fams.first.id;
        return _ControlsCard(familyId: familyId);
      },
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.familyId});
  final String? familyId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(title: 'Family controls'),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Column(
            children: [
              _ScreenTimeControlTile(familyId: familyId),
              const Divider(height: 1, indent: 64),
              _ControlTile(
                icon: Icons.apps_rounded,
                color: AppColors.info,
                title: 'App rules',
                subtitle: 'Block apps, per-app limits',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppRulesScreen(familyId: familyId),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 64),
              _WebFilterControlTile(familyId: familyId),
            ],
          ),
        ),
      ],
    );
  }
}

/// The "Your family" section. Demo cards when [uid] is null; live Firestore
/// families/children when set.
class _FamilyChildren extends StatefulWidget {
  const _FamilyChildren({super.key, required this.uid, this.onSync});
  final String? uid;
  final VoidCallback? onSync;

  @override
  State<_FamilyChildren> createState() => _FamilyChildrenState();
}

class _FamilyChildrenState extends State<_FamilyChildren> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-evaluate heartbeat freshness periodically, since a device that has
    // gone silent won't push a new Firestore snapshot to trigger a rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The "Sync" + "Add child" buttons shown next to the family section title.
  /// When [atLimit] is set the child limit has been reached, so adding is
  /// blocked with an explanatory message instead.
  Widget _headerActions(VoidCallback onAdd,
      {bool atLimit = false, int maxChildren = 0}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onSync != null)
          TextButton.icon(
            onPressed: widget.onSync,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sync'),
          ),
        TextButton.icon(
          onPressed: atLimit
              ? () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(
                    'Child limit reached ($maxChildren). Ask your admin to raise it.',
                  ),
                ))
              : onAdd,
          icon: Icon(atLimit ? Icons.lock_outline_rounded : Icons.add,
              size: 18),
          label: const Text('Add child'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    if (uid == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            title: 'Your family (${demoChildren.length})',
            trailing: _headerActions(() => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddChildScreen()),
                )),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...demoChildren.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ChildCard(child: c),
              )),
        ],
      );
    }

    final repo = FamilyRepository.instance;
    return StreamBuilder<AppUser?>(
      stream: UserRepository.instance.watch(uid),
      builder: (context, userSnap) {
        final maxChildren = userSnap.data?.maxChildren ?? kDefaultMaxChildren;
        return StreamBuilder<List<FamilyModel>>(
          stream: repo.watchFamilies(uid),
          builder: (context, famSnap) {
            if (famSnap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final families = famSnap.data ?? const [];
            if (families.isEmpty) {
              return _CreateFamilyCard(
                onCreate: () =>
                    repo.createFamily(name: 'My Family', ownerUid: uid),
              );
            }
            final family = families.first;
            return StreamBuilder<List<Child>>(
              stream: repo.watchChildren(family.id),
              builder: (context, kidSnap) {
                final kids = kidSnap.data ?? const <Child>[];
                final atLimit = kids.length >= maxChildren;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(
                      title: kids.isEmpty
                          ? family.name
                          : '${family.name} (${kids.length})',
                      trailing: _headerActions(
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddChildScreen(familyId: family.id),
                          ),
                        ),
                        atLimit: atLimit,
                        maxChildren: maxChildren,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (kids.isEmpty)
                      const _EmptyChildren()
                    else
                      Column(
                        children: kids
                            .map((c) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child:
                                      _ChildCard(child: c, familyId: family.id),
                                ))
                            .toList(),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CreateFamilyCard extends StatelessWidget {
  const _CreateFamilyCard({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Icon(Icons.family_restroom_rounded,
                size: 44, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            const Text('Create your family',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Set up your family to start adding children and devices.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onCreate, child: const Text('Create family')),
          ],
        ),
      ),
    );
  }
}

class _EmptyChildren extends StatelessWidget {
  const _EmptyChildren();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: const [
            Icon(Icons.child_care_rounded, size: 44, color: AppColors.textMuted),
            SizedBox(height: AppSpacing.sm),
            Text('No children yet',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Tap “Add child” to create a pairing code and link a device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, this.familyId});
  final Child child;
  final String? familyId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) =>
                  ChildDetailScreen(child: child, familyId: familyId)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: child.avatarColor,
                child: Text(
                  child.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      child.deviceModel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StatusPill(
                      label: child.effectiveStatus.label,
                      color: child.effectiveStatus.color,
                      icon: child.effectiveStatus.icon,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor = AppColors.danger,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional red status pill (e.g. "PAUSED", "BEDTIME").
  final String? badge;

  /// Colour of the status pill.
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, color: Colors.white, size: 8),
                  const SizedBox(width: 4),
                  Text(badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
