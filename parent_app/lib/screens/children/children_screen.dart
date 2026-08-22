import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/child.dart';
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

  bool matches(Child c) => switch (this) {
        ChildFilter.all => true,
        ChildFilter.online => c.effectiveStatus == ChildStatus.online,
        ChildFilter.offline => c.effectiveStatus == ChildStatus.offline,
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

  @override
  void initState() {
    super.initState();
    if (Db.ready) {
      _sub = FamilyRepository.instance.watchAllChildren().listen((kids) {
        if (mounted) setState(() => _kids = kids);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Profiles missing a permission sort first — they're the ones needing a look.
  static int _priority(Child c) =>
      c.effectiveStatus == ChildStatus.offline ? 0 : 1;

  List<({Child child, String familyId})> get _visible {
    final q = _query.trim().toLowerCase();
    final out = _kids.where((k) {
      if (!_filter.matches(k.child)) return false;
      if (q.isEmpty) return true;
      return k.child.name.toLowerCase().contains(q);
    }).toList();
    out.sort((a, b) {
      final p = _priority(a.child).compareTo(_priority(b.child));
      if (p != 0) return p;
      return a.child.name.toLowerCase().compareTo(b.child.name.toLowerCase());
    });
    return out;
  }

  int _countFor(ChildFilter f) =>
      _kids.where((k) => f.matches(k.child)).length;

  bool _atLimit(BuildContext context) {
    final fid = widget.familyId;
    final ownCount = _kids.where((k) => k.familyId == fid).length;
    if (widget.maxChildren > 0 && ownCount >= widget.maxChildren) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            'Child limit reached (${widget.maxChildren}). Ask your admin to raise it.',
          ),
        ));
      return true;
    }
    return false;
  }

  void _newProfile(BuildContext context) {
    final fid = widget.familyId;
    if (fid == null || _atLimit(context)) return;
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
  });

  final Child child;
  final String? familyId;

  @override
  Widget build(BuildContext context) {
    final status = child.effectiveStatus;
    final online = status == ChildStatus.online;
    final surface = AppColors.surfaceOf(context);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                        border: Border.all(color: status.color, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: child.avatarColor,
                        child: Text(
                          child.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: status.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: surface, width: 2),
                        ),
                        child: Icon(
                          online
                              ? Icons.check_rounded
                              : Icons.close_rounded,
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
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(
                            color: status.color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
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
