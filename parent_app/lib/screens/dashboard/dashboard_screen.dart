import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_update_repository.dart';
import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/rules_repository.dart';
import '../../data/user_repository.dart';
import '../../config.dart';
import '../../models/app_user.dart';
import '../../models/child.dart';
import '../../models/family.dart';
import '../../models/screen_time_rule.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/profile_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../app_rules/app_rules_screen.dart';
import '../child_detail/child_detail_screen.dart';
import '../children/children_screen.dart';
import '../children/new_profile_dialog.dart';
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
  bool get _live => widget.uid != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: const BrandLockup(markSize: 32),
        actions: const [
          ThemeToggleButton(),
          ProfileButton(),
          SizedBox(width: AppSpacing.xs)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GreetingHeader(uid: _live ? uid : null),
            const SizedBox(height: AppSpacing.md),
            _FamilyChildren(uid: _live ? uid : null),
            const SizedBox(height: AppSpacing.md),
            _FamilyControls(uid: _live ? uid : null),
          ],
        ),
      ),
    );
  }
}

/// The banner that opens the home screen: the day, a greeting, and how the
/// family is doing right now.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({this.uid});

  final String? uid;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _date {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Clipped so the oversized shield can bleed past the edges without
      // squaring off the corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.raised,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -26,
            bottom: -38,
            child: Icon(
              Icons.shield_rounded,
              size: 160,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _date.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _greeting,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'An Initiative by ISKCON Brahmapur',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
                const SizedBox(height: AppSpacing.sm),
                _FamilyPulse(uid: uid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line answer to "is everything alright?", inside the banner.
class _FamilyPulse extends StatelessWidget {
  const _FamilyPulse({required this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const _PulseRow(profiles: 0, protected: 0, attention: 0);
    }
    return StreamBuilder<List<({Child child, String familyId})>>(
      stream: FamilyRepository.instance.watchAllChildren(),
      builder: (context, snap) {
        final kids = snap.data ?? const <({Child child, String familyId})>[];
        final protected = kids
            .where((k) => k.child.effectiveStatus == ChildStatus.online)
            .length;
        return _PulseRow(
          profiles: kids.length,
          protected: protected,
          attention: kids.length - protected,
        );
      },
    );
  }
}

class _PulseRow extends StatelessWidget {
  const _PulseRow({
    required this.profiles,
    required this.protected,
    required this.attention,
  });

  final int profiles;
  final int protected;
  final int attention;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PulseStat(
            value: profiles, label: profiles == 1 ? 'Profile' : 'Profiles'),
        _PulseDivider(),
        _PulseStat(value: protected, label: 'Protected'),
        _PulseDivider(),
        _PulseStat(value: attention, label: 'Need attention'),
      ],
    );
  }
}

class _PulseDivider extends StatelessWidget {
  const _PulseDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: Colors.white.withValues(alpha: 0.18),
      );
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
        title: 'Screen time',
        subtitle: 'Bedtime & pause',
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
          title: 'Screen time',
          subtitle: 'Bedtime & pause',
          badge: badge,
          onTap: () => _open(context),
        );
      },
    );
  }
}

/// The Web-filter control tile. Safe browsing can't be switched off by anyone,
/// so the badge is a statement of fact rather than a live flag.
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
    return _ControlTile(
      icon: Icons.public_rounded,
      color: AppColors.success,
      title: 'Web filter',
      subtitle: 'Safe browsing',
      badge: 'ON',
      badgeColor: AppColors.success,
      onTap: () => _open(context),
    );
  }
}

/// Family-wide control tiles. Supplies the live familyId (when connected) so
/// editors can persist; opens in demo mode otherwise.
class _FamilyControls extends StatelessWidget {
  const _FamilyControls({required this.uid});
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
        // Side by side rather than stacked: three full-width rows pushed the
        // home screen past a single screenful.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ScreenTimeControlTile(familyId: familyId)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ControlTile(
                  icon: Icons.apps_rounded,
                  color: AppColors.info,
                  title: 'App rules',
                  subtitle: 'Block apps',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppRulesScreen(familyId: familyId),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _WebFilterControlTile(familyId: familyId)),
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
  const _FamilyChildren({required this.uid});
  final String? uid;

  @override
  State<_FamilyChildren> createState() => _FamilyChildrenState();
}

class _FamilyChildrenState extends State<_FamilyChildren> {
  Timer? _ticker;
  bool _provisioning = false;
  int _latestVersionCode = 0;
  StreamSubscription<AppUpdateConfig>? _updateSub;

  @override
  void initState() {
    super.initState();
    // Re-evaluate heartbeat freshness periodically, since a device that has
    // gone silent won't push a new Firestore snapshot to trigger a rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Track the latest published child-app version so we can flag devices that
    // haven't updated.
    if (Db.ready) {
      _updateSub = AppUpdateRepository.instance.watch().listen((c) {
        if (mounted) setState(() => _latestVersionCode = c.versionCode);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _updateSub?.cancel();
    super.dispose();
  }

  /// "See all" opens the Profiles page â€” which is also where profiles are
  /// created and devices paired, so it shows even while the family is empty.
  Widget _headerActions({VoidCallback? onSeeAll}) {
    if (onSeeAll == null) return const SizedBox.shrink();
    return TextButton(onPressed: onSeeAll, child: const Text('See all'));
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final canEdit = AccessScope.of(context);
    if (uid == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            title: 'Your family',
            trailing: _headerActions(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _FamilyStrip(
            kids: [
              for (final c in demoChildren) (child: c, familyId: ''),
            ],
          ),
        ],
      );
    }

    final repo = FamilyRepository.instance;
    return StreamBuilder<AppUser?>(
      stream: UserRepository.instance.watch(uid),
      builder: (context, userSnap) {
        final maxChildren = userSnap.data?.maxChildren ?? kDefaultMaxChildren;
        // Every org admin sees ALL children across all families.
        return StreamBuilder<List<({Child child, String familyId})>>(
          stream: repo.watchAllChildren(),
          builder: (context, kidSnap) {
            if (kidSnap.connectionState == ConnectionState.waiting &&
                !kidSnap.hasData) {
              return _childrenLoader();
            }
            final kids = kidSnap.data ?? const [];
            // The org admin's own family is only the target for "Add child";
            // provision it lazily for editors. Viewing all children never
            // depends on having your own family.
            return StreamBuilder<List<FamilyModel>>(
              stream: repo.watchFamilies(uid),
              builder: (context, famSnap) {
                final families = famSnap.data ?? const <FamilyModel>[];
                final famReady =
                    famSnap.connectionState != ConnectionState.waiting;
                final ownFamilyId =
                    families.isEmpty ? null : families.first.id;
                if (canEdit && famReady && families.isEmpty && !_provisioning) {
                  _provisioning = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    FamilyRepository.instance
                        .createFamily(name: 'My Family', ownerUid: uid);
                  });
                }
                if (families.isNotEmpty) _provisioning = false;

                final canAdd = canEdit && ownFamilyId != null;
                void openAll([ChildFilter filter = ChildFilter.all]) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChildrenScreen(
                        children: kids,
                        latestVersionCode: _latestVersionCode,
                        initialFilter: filter,
                        familyId: canAdd ? ownFamilyId : null,
                        maxChildren: maxChildren,
                      ),
                    ),
                  );
                }

                // The strip's Add chip creates a profile; devices are paired
                // from inside the profile.
                void addProfile() {
                  final ownCount = kids
                      .where((k) => k.familyId == ownFamilyId)
                      .length;
                  if (ownCount >= maxChildren) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(
                          'Child limit reached ($maxChildren). Ask your admin to raise it.',
                        ),
                      ));
                    return;
                  }
                  showNewProfileDialog(context, ownFamilyId!);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(
                      title: 'Your family',
                      trailing: _headerActions(onSeeAll: openAll),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (kids.isEmpty)
                      _EmptyChildren(
                        canAdd: canAdd,
                        onAdd: canAdd ? addProfile : null,
                      )
                    else
                      _FamilyStrip(
                        kids: kids,
                        onAdd: canAdd ? addProfile : null,
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

  Widget _childrenLoader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
}

class _EmptyChildren extends StatelessWidget {
  const _EmptyChildren({this.canAdd = true, this.onAdd});
  final bool canAdd;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const Icon(Icons.child_care_rounded,
                size: 34, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.xs),
            const Text('No profiles yet',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              canAdd
                  ? 'Create a profile for each child; devices are added from '
                      'inside the profile.'
                  : 'Children added by any org admin appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondaryOf(context)),
            ),
            if (onAdd != null) ...[
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('New profile'),
              ),
            ],
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

/// The family as people, the Qustodio way: one avatar per child with a status
/// ring, scrolling horizontally. Tap opens the child; the last chip adds a
/// device.
class _FamilyStrip extends StatelessWidget {
  const _FamilyStrip({required this.kids, this.onAdd});

  final List<({Child child, String familyId})> kids;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      child: SizedBox(
        height: 88,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final k in kids)
              _AvatarChip(child: k.child, familyId: k.familyId),
            if (onAdd != null) _AddChip(onTap: onAdd!),
          ],
        ),
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  const _AvatarChip({required this.child, required this.familyId});
  final Child child;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final status = child.effectiveStatus;
    final online = status == ChildStatus.online;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChildDetailScreen(
            child: child,
            familyId: familyId.isEmpty ? null : familyId,
          ),
        ),
      ),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // The ring is the status: green for protected, amber otherwise.
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: status.color, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: child.avatarColor,
                    child: Text(
                      child.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.surfaceOf(context), width: 2),
                    ),
                    child: Icon(
                      online
                          ? Icons.check_rounded
                          : Icons.priority_high_rounded,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              child.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(height: 5),
            const Text(
              'Add',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
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

  /// Optional status pill (e.g. "ON", "PAUSED", "BEDTIME").
  final String? badge;

  /// Colour of the status pill.
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.18),
                        color.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                // The live badge replaces the subtitle rather than adding a
                // line, so all three tiles stay the same height.
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(badge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        )),
                  )
                else
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
