import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/tags_repository.dart';
import '../../models/child.dart';
import '../../models/device.dart';
import '../../models/tag.dart';
import '../../screens/child_detail/child_detail_screen.dart';
import '../../screens/children/new_profile_dialog.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';

/// Which profiles the grid is showing.
enum ChildFilter { all, online, offline }

extension ChildFilterInfo on ChildFilter {
  String get label => switch (this) {
    ChildFilter.all => 'All',
    ChildFilter.online => 'Protected',
    ChildFilter.offline => 'Needs attention',
  };

  bool matches(Child c, ChildStatus status) => switch (this) {
    ChildFilter.all => true,
    ChildFilter.online => c.paired && status == ChildStatus.online,
    ChildFilter.offline => c.paired && status != ChildStatus.online,
  };
}

/// Every child profile as a compact tile grid. Profiles are the unit a parent
/// manages — devices pair onto a profile — and this page is also where new
/// devices are added.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({
    super.key,
    required this.children,
    this.latestVersionCode = 0,
    this.initialFilter = ChildFilter.all,
    this.familyId,
    this.maxChildren = 0,
  });

  final List<({Child child, String familyId})> children;
  final int latestVersionCode;
  final ChildFilter initialFilter;

  /// The signed-in parent's own family — the target for "Add device".
  final String? familyId;
  final int maxChildren;

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late ChildFilter _filter = widget.initialFilter;

  // Null means "every tag". Tags come from the family, so one listener serves
  // the whole page however many profiles there are.
  String? _tagId;
  List<FamilyTag> _tags = const [];
  StreamSubscription<List<FamilyTag>>? _tagSub;

  // The list arrives from the caller so the page opens instantly, then follows
  // Firestore: creating or deleting a profile used to leave this page stale
  // until it was closed and reopened.
  late List<({Child child, String familyId})> _kids = widget.children;
  StreamSubscription<List<({Child child, String familyId})>>? _sub;

  @override
  void initState() {
    super.initState();
    if (Db.ready) {
      _sub = FamilyRepository.instance.watchMyChildren().listen((kids) {
        if (!mounted) return;
        setState(() => _kids = kids);
      });
      final fid = widget.familyId;
      if (fid != null && fid.isNotEmpty) {
        _tagSub = TagsRepository.instance.watch(fid).listen((tags) {
          if (!mounted) return;
          setState(() {
            _tags = tags;
            // A tag the admin deleted must not keep filtering the list.
            if (_tagId != null && !tags.any((t) => t.id == _tagId)) {
              _tagId = null;
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tagSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({Child child, String familyId})> get _visible {
    final q = _query.trim().toLowerCase();
    final out = _kids.where((k) {
      if (!_filter.matches(k.child, k.child.effectiveStatus)) return false;
      if (_tagId != null && !k.child.tagIds.contains(_tagId)) return false;
      if (q.isEmpty) return true;
      return k.child.name.toLowerCase().contains(q);
    }).toList();
    // Straight A-Z. Sorting problems to the top moved profiles around as
    // devices reported, so the same child was never in the same place twice;
    // the "Needs attention" chip is the way to find them instead.
    out.sort(
      (a, b) =>
          a.child.name.toLowerCase().compareTo(b.child.name.toLowerCase()),
    );
    return out;
  }

  // Both filters count against each other, so "Needs attention" inside a tag
  // reads honestly rather than showing the whole family's total.
  int _countFor(ChildFilter f) => _kids
      .where(
        (k) =>
            f.matches(k.child, k.child.effectiveStatus) &&
            (_tagId == null || k.child.tagIds.contains(_tagId)),
      )
      .length;

  int _countForTag(String? tagId) => _kids
      .where(
        (k) =>
            _filter.matches(k.child, k.child.effectiveStatus) &&
            (tagId == null || k.child.tagIds.contains(tagId)),
      )
      .length;

  void _newProfile(BuildContext context) {
    final fid = widget.familyId;
    if (fid == null) return;
    showNewProfileDialog(context, fid);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final canAdd = widget.familyId != null && AccessScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Profiles (${_kids.length})'),
        actions: [
          if (_tags.isNotEmpty)
            _TagFilterButton(
              tags: _tags,
              selectedId: _tagId,
              countFor: _countForTag,
              onSelected: (id) => setState(() => _tagId = id),
            ),
          if (canAdd)
            IconButton(
              tooltip: 'New profile',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () => _newProfile(context),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search profiles',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final f in ChildFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Center(
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${f.label} (${_countFor(f)})'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No profiles match this view.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.xxl,
                    ),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => ProfileTile(
                      child: visible[i].child,
                      familyId: visible[i].familyId,
                      latestVersionCode: widget.latestVersionCode,
                      tags: _tags,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One profile as a full-width row: avatar with a status ring, the name and
/// its state. Full width so long names always read.
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.child,
    this.familyId,
    this.latestVersionCode = 0,
    this.tags = const [],
  });

  final Child child;
  final String? familyId;

  /// The newest published build, for flagging devices that haven't taken it.
  final int latestVersionCode;

  /// The family's tags, for turning this profile's tag ids into names.
  final List<FamilyTag> tags;

  /// True when any linked device is still on an older build. Devices that have
  /// never reported a version are skipped rather than guessed at.
  bool _updatePending(List<Device> devices) =>
      latestVersionCode > 0 &&
      devices.any(
        (d) => d.appVersionCode > 0 && d.appVersionCode < latestVersionCode,
      );

  @override
  Widget build(BuildContext context) {
    final devices = child.devices;
    // Each device stamps the profile document, so its status is whichever one
    // reported last. The devices themselves are the truth.
    final worst = ProfileStatus.worst(devices);
    final status = child.effectiveStatus;
    final removed = worst != null
        ? worst.likelyRemoved || worst.removalUnlocked
        : status == ChildStatus.removed;
    final statusColor = worst?.statusColor ?? status.color;
    final ok = worst != null
        ? worst.severity == 0
        : status == ChildStatus.online;
    // No device linked yet — the profile has no status to show.
    final ringColor = child.paired ? statusColor : AppColors.borderOf(context);
    final surface = AppColors.surfaceOf(context);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ChildDetailScreen(child: child, familyId: familyId),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md - 2,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ringColor, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: removed
                            ? AppColors.danger
                            : child.avatarColor,
                        child: removed
                            ? const Icon(
                                Icons.gpp_bad_rounded,
                                color: Colors.white,
                                size: 24,
                              )
                            : Text(
                                child.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                    ),
                    if (child.paired)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 15,
                          height: 15,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: surface, width: 2),
                          ),
                          child: Icon(
                            ok ? Icons.check_rounded : Icons.close_rounded,
                            size: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      if (child.paired)
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // No status wording here — the ring and the badge
                            // on the avatar already say it.
                            // Which devices those are: the status above is the
                            // worst of them, so the count is what tells a
                            // parent whether anything else is linked.
                            if (devices.isNotEmpty)
                              _MutedPill(
                                icon: devices.length == 1
                                    ? devices.first.icon
                                    : Icons.devices_rounded,
                                // One device needs no words — the mark says
                                // which platform, and the name is on the
                                // profile itself.
                                label: devices.length == 1
                                    ? ''
                                    : '${devices.length} devices',
                              ),
                            // Rolling out an update is otherwise invisible:
                            // there was no way to tell which devices had
                            // actually taken it.
                            if (_updatePending(devices))
                              _StatusPill(
                                label: 'Update pending',
                                color: AppColors.warning,
                              ),
                            // The groups this profile belongs to, so a filtered
                            // list still says why each row is in it.
                            for (final t in tags.where(
                              (t) => child.tagIds.contains(t.id),
                            ))
                              _StatusPill(label: t.name, color: t.color),
                          ],
                        )
                      else
                        const Text(
                          'No device linked',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The profile's state, coloured by how much attention it needs.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tag filter, as a single app-bar control.
///
/// `PopupMenuButton` treats a null result as a dismissal, so "All tags"
/// travels as an empty string rather than null.
class _TagFilterButton extends StatelessWidget {
  const _TagFilterButton({
    required this.tags,
    required this.selectedId,
    required this.countFor,
    required this.onSelected,
  });

  final List<FamilyTag> tags;
  final String? selectedId;
  final int Function(String? tagId) countFor;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    FamilyTag? current;
    for (final t in tags) {
      if (t.id == selectedId) {
        current = t;
        break;
      }
    }
    final on = current != null;
    final accent = current?.color ?? AppColors.textSecondaryOf(context);
    return PopupMenuButton<String>(
      tooltip: 'Filter by tag',
      position: PopupMenuPosition.under,
      onSelected: (v) => onSelected(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '',
          child: Text('All tags (${countFor(null)})'),
        ),
        for (final t in tags)
          PopupMenuItem(
            value: t.id,
            child: Row(
              children: [
                CircleAvatar(backgroundColor: t.color, radius: 6),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(t.name, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${countFor(t.id)}',
                  style: TextStyle(
                    color: AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(
              color: on
                  ? accent.withValues(alpha: 0.55)
                  : AppColors.borderOf(context),
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on)
                CircleAvatar(backgroundColor: accent, radius: 5)
              else
                Icon(Icons.sell_outlined, size: 15, color: accent),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  current?.name ?? 'All tags',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? accent : AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 20,
                color: on ? accent : AppColors.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet fact next to the status — never competes with it for attention.
class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textSecondaryOf(context)),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
