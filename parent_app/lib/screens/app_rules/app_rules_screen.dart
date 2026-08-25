import 'package:flutter/material.dart';

import '../../data/app_rules_repository.dart';
import '../../data/db.dart';
import '../../models/app_rule.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/feedback.dart';
import '../../widgets/read_only_banner.dart';

/// Which apps the list is showing.
enum _AppFilter { all, blocked, banking }

/// App rules editor: search installed apps, block them, or set a per-app daily
/// limit. Persists to Firestore when [familyId] is set and connected.
class AppRulesScreen extends StatefulWidget {
  const AppRulesScreen({
    super.key,
    this.childName,
    this.familyId,
    this.childId,
    this.deviceId,
    this.platform,
  });

  final String? childName;
  final String? familyId;
  final String? childId;
  final String? deviceId;
  final String? platform;

  @override
  State<AppRulesScreen> createState() => _AppRulesScreenState();
}

class _AppRulesScreenState extends State<AppRulesScreen> {
  late List<AppRule> _apps;
  bool _loading = false;
  String _query = '';
  bool _canEdit = true;
  _AppFilter _filter = _AppFilter.all;

  bool get _live => widget.familyId != null && Db.ready;

  @override
  void initState() {
    super.initState();
    if (_live) {
      // Start empty and show a loader; the child device's real apps load in.
      _apps = [];
      _loading = true;
      _load();
    } else {
      _apps = demoAppRules();
    }
  }

  Future<void> _load() async {
    try {
      final reported = widget.childId != null
          ? await AppRulesRepository.instance.loadInstalledAppsForChild(
              widget.familyId!,
              widget.childId!,
              deviceId: widget.deviceId,
              platform: widget.platform,
            )
          : await AppRulesRepository.instance.loadInstalledApps(
              widget.familyId!,
            );
      final saved = await AppRulesRepository.instance.load(
        widget.familyId!,
        childId: widget.childId,
      );
      // On a child's screen the family-wide rules apply too — the device
      // blocks when either does, so show the same merged picture.
      final family = widget.childId == null
          ? const <String, AppRuleData>{}
          : await AppRulesRepository.instance.load(widget.familyId!);
      if (!mounted) return;
      setState(() {
        _apps = reported
            .map(
              (a) =>
                  AppRule.installed(a.packageName, a.appName, owners: a.owners),
            )
            .toList();
        for (final app in _apps) {
          final r = saved[app.packageName];
          if (r != null) {
            app.blocked = r.blocked;
            app.dailyLimitMinutes = r.dailyLimitMinutes;
            app.bankingAllowed = r.bankingAllowed;
          }
          final f = family[app.packageName];
          if (f != null) {
            app.blockedByFamily = f.blocked;
            app.bankingByFamily = f.bankingAllowed;
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Otherwise this looks identical to "the child has no apps yet".
      context.showError('Couldn’t load app rules', e);
    }
  }

  /// Writes one app's rule, undoing [revert] if the save is rejected — a switch
  /// that stays on after a failed write would tell the parent an app is blocked
  /// when the child device never got the rule.
  Future<void> _persist(AppRule app, VoidCallback revert) async {
    if (!_live || !_canEdit) return;
    try {
      await AppRulesRepository.instance.setRule(
        widget.familyId!,
        packageName: app.packageName,
        appName: app.appName,
        blocked: app.blocked,
        dailyLimitMinutes: app.dailyLimitMinutes,
        bankingAllowed: app.bankingAllowed,
        childId: widget.childId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(revert);
      context.showError('Couldn’t save the rule for ${app.appName}', e);
    }
  }

  List<AppRule> get _filtered {
    final q = _query.trim().toLowerCase();
    return _apps.where((a) {
      if (q.isNotEmpty && !a.appName.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _AppFilter.all => true,
        _AppFilter.blocked => a.effectivelyBlocked,
        _AppFilter.banking => a.effectivelyBanking,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    _canEdit = AccessScope.of(context);
    final title = widget.childName == null
        ? 'App rules'
        : 'App rules · ${widget.childName}';
    final blocked = _apps.where((a) => a.effectivelyBlocked).length;
    final banking = _apps.where((a) => a.effectivelyBanking).length;
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (!_canEdit)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: ReadOnlyBanner(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: _RulesSummary(
              total: _apps.length,
              blocked: blocked,
              banking: banking,
              filter: _filter,
              // Tapping the active stat clears it, so "all" needs no chip.
              onFilter: (f) =>
                  setState(() => _filter = _filter == f ? _AppFilter.all : f),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apps.isEmpty
                ? const EmptyState(
                    icon: Icons.apps_rounded,
                    title: 'No apps yet',
                    message: 'Apps appear here once the child device syncs.',
                  )
                : list.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No apps in this view',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.xxl,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _AppTile(
                      app: list[i],
                      canEdit: _canEdit,
                      onBlockChanged: (v) {
                        if (!_canEdit) return;
                        final app = list[i];
                        final was = app.blocked;
                        setState(() => app.blocked = v);
                        _persist(app, () => app.blocked = was);
                      },
                      onBankingChanged: (v) {
                        if (!_canEdit) return;
                        final app = list[i];
                        final was = app.bankingAllowed;
                        setState(() => app.bankingAllowed = v);
                        _persist(app, () => app.bankingAllowed = was);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The headline for the list: how many apps are installed, and how many carry
/// a rule. The two counts double as filters.
class _RulesSummary extends StatelessWidget {
  const _RulesSummary({
    required this.total,
    required this.blocked,
    required this.banking,
    required this.filter,
    required this.onFilter,
  });

  final int total;
  final int blocked;
  final int banking;
  final _AppFilter filter;
  final ValueChanged<_AppFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APPS ACROSS YOUR DEVICES',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _Stat(
                value: blocked,
                label: 'Blocked',
                icon: Icons.block_rounded,
                active: filter == _AppFilter.blocked,
                onTap: () => onFilter(_AppFilter.blocked),
              ),
              _Stat(
                value: banking,
                label: 'Temp access',
                icon: Icons.account_balance_rounded,
                active: filter == _AppFilter.banking,
                onTap: () => onFilter(_AppFilter.banking),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final int value;
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 5),
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.canEdit,
    required this.onBlockChanged,
    required this.onBankingChanged,
  });

  final AppRule app;
  final bool canEdit;
  final ValueChanged<bool> onBlockChanged;
  final ValueChanged<bool> onBankingChanged;

  @override
  Widget build(BuildContext context) {
    final owners = app.owners.isNotEmpty ? app.owners.join(', ') : null;
    // A family-wide rule can't be undone from one child's screen, so its
    // controls are shown in their real state but locked.
    final lockBlock = app.blockedByFamily;
    final lockBanking = app.bankingByFamily;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: app.effectivelyBlocked
              ? AppColors.danger.withValues(alpha: 0.35)
              : AppColors.borderOf(context),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: app.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              app.initials,
              style: TextStyle(
                color: app.color,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (owners != null ||
                    app.effectivelyBlocked ||
                    app.effectivelyBanking) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (app.effectivelyBlocked)
                        const _Tag(label: 'Blocked', color: AppColors.danger),
                      if (app.effectivelyBanking)
                        const _Tag(
                          label: 'Temp access',
                          color: AppColors.success,
                          icon: Icons.account_balance_rounded,
                        ),
                      if (lockBlock || lockBanking)
                        const _Tag(
                          label: 'All children',
                          color: AppColors.info,
                          icon: Icons.groups_2_rounded,
                        ),
                      if (owners != null)
                        Text(
                          owners,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: app.effectivelyBlocked,
            onChanged: (canEdit && !lockBlock) ? onBlockChanged : null,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: canEdit && !lockBanking,
            position: PopupMenuPosition.under,
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
            onSelected: (v) {
              if (v == 'banking') onBankingChanged(!app.bankingAllowed);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'banking',
                checked: app.effectivelyBanking,
                child: const Text('Allow in Temp access mode'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small state chip on an app row — what rule it carries, at a glance.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
