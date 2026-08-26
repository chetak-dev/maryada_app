import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/device_repository.dart';
import '../../data/family_repository.dart';
import '../../models/child.dart';
import '../../models/device.dart';
import '../../screens/child_detail/child_detail_screen.dart';
import '../../screens/children/new_profile_dialog.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/child_devices.dart';

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

  // The list arrives from the caller so the page opens instantly, then follows
  // Firestore: creating or deleting a profile used to leave this page stale
  // until it was closed and reopened.
  late List<({Child child, String familyId})> _kids = widget.children;
  StreamSubscription<List<({Child child, String familyId})>>? _sub;

  // The devices of every listed profile, held here rather than in each tile so
  // the filter counts and the tiles can never tell the parent two different
  // things about the same profile.
  final Map<String, List<Device>> _devices = {};
  final Map<String, StreamSubscription<List<Device>>> _deviceSubs = {};

  @override
  void initState() {
    super.initState();
    _syncDeviceSubs(_kids);
    if (Db.ready) {
      _sub = FamilyRepository.instance.watchMyChildren().listen((kids) {
        if (!mounted) return;
        setState(() => _kids = kids);
        _syncDeviceSubs(kids);
      });
    }
  }

  void _syncDeviceSubs(List<({Child child, String familyId})> kids) {
    if (!Db.ready) return;
    final wanted = {for (final k in kids) k.child.id: k.familyId};
    for (final id in _deviceSubs.keys.toList()) {
      if (!wanted.containsKey(id)) {
        _deviceSubs.remove(id)?.cancel();
        _devices.remove(id);
      }
    }
    for (final entry in wanted.entries) {
      if (_deviceSubs.containsKey(entry.key) || entry.value.isEmpty) continue;
      _deviceSubs[entry.key] = DeviceRepository.instance
          .watch(entry.value, entry.key)
          .listen((devices) {
        if (mounted) setState(() => _devices[entry.key] = devices);
      });
    }
  }

  /// A profile's status, taken from its devices. The profile document is
  /// stamped by every device, so on its own it reports whichever reported last.
  ChildStatus _statusOf(Child c) {
    final devices = _devices[c.id];
    final worst = devices == null ? null : ProfileStatus.worst(devices);
    if (worst == null) return c.effectiveStatus;
    if (worst.likelyRemoved || worst.removalUnlocked) return ChildStatus.removed;
    return worst.severity == 0 ? ChildStatus.online : ChildStatus.offline;
  }

  @override
  void dispose() {
    for (final sub in _deviceSubs.values) {
      sub.cancel();
    }
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({Child child, String familyId})> get _visible {
    final q = _query.trim().toLowerCase();
    final out = _kids.where((k) {
      if (!_filter.matches(k.child, _statusOf(k.child))) return false;
      if (q.isEmpty) return true;
      return k.child.name.toLowerCase().contains(q);
    }).toList();
    // Straight A-Z. Sorting problems to the top moved profiles around as
    // devices reported, so the same child was never in the same place twice;
    // the "Needs attention" chip is the way to find them instead.
    out.sort(
      (a, b) => a.child.name.toLowerCase().compareTo(b.child.name.toLowerCase()),
    );
    return out;
  }

  int _countFor(ChildFilter f) =>
      _kids.where((k) => f.matches(k.child, _statusOf(k.child))).length;

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
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
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
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final f in ChildFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text('${f.label} (${_countFor(f)})'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
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
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                        AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => ProfileTile(
                      child: visible[i].child,
                      familyId: visible[i].familyId,
                      devices: _devices[visible[i].child.id],
                      latestVersionCode: widget.latestVersionCode,
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
    this.devices,
    this.latestVersionCode = 0,
  });

  final Child child;
  final String? familyId;

  /// Supplied when the caller already watches them, so the list doesn't open a
  /// second subscription per row.
  final List<Device>? devices;

  /// The newest published build, for flagging devices that haven't taken it.
  final int latestVersionCode;

  /// True when any linked device is still on an older build. Devices that have
  /// never reported a version are skipped rather than guessed at.
  bool _updatePending(List<Device> devices) =>
      latestVersionCode > 0 &&
      devices.any(
        (d) => d.appVersionCode > 0 && d.appVersionCode < latestVersionCode,
      );

  @override
  Widget build(BuildContext context) {
    final known = devices;
    if (known != null) return _build(context, known);
    return ChildDevices(
      familyId: familyId,
      childId: child.id,
      builder: (context, devices) => _build(context, devices),
    );
  }

  Widget _build(BuildContext context, List<Device> devices) {
    // Each device stamps the profile document, so its status is whichever one
    // reported last. The devices themselves are the truth.
    final worst = ProfileStatus.worst(devices);
    final status = child.effectiveStatus;
    final removed = worst != null
        ? worst.likelyRemoved || worst.removalUnlocked
        : status == ChildStatus.removed;
    final statusColor = worst?.statusColor ?? status.color;
    final statusLabel = worst?.statusLabel ?? status.label;
    final ok = worst != null
        ? worst.severity == 0
        : status == ChildStatus.online;
    // No device linked yet — the profile has no status to show.
    final ringColor =
        child.paired ? statusColor : AppColors.borderOf(context);
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
                    ChildDetailScreen(child: child, familyId: familyId)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
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
                        backgroundColor:
                            removed ? AppColors.danger : child.avatarColor,
                        child: removed
                            ? const Icon(Icons.gpp_bad_rounded,
                                color: Colors.white, size: 24)
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
                            _StatusPill(
                              label: statusLabel,
                              color: statusColor,
                            ),
                            // Which devices those are: the status above is the
                            // worst of them, so the count is what tells a
                            // parent whether anything else is linked.
                            if (devices.isNotEmpty)
                              _MutedPill(
                                icon: devices.length == 1
                                    ? devices.first.icon
                                    : Icons.devices_rounded,
                                label: devices.length == 1
                                    ? devices.first.label
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
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textMuted),
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
      ),
    );
  }
}
