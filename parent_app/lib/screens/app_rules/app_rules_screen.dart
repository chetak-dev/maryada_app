import 'package:flutter/material.dart';

import '../../data/app_rules_repository.dart';
import '../../data/db.dart';
import '../../models/app_rule.dart';
import '../../theme/tokens.dart';

/// App rules editor: search installed apps, block them, or set a per-app daily
/// limit. Persists to Firestore when [familyId] is set and connected.
class AppRulesScreen extends StatefulWidget {
  const AppRulesScreen({super.key, this.childName, this.familyId, this.childId});

  final String? childName;
  final String? familyId;
  final String? childId;

  @override
  State<AppRulesScreen> createState() => _AppRulesScreenState();
}

class _AppRulesScreenState extends State<AppRulesScreen> {
  late List<AppRule> _apps;
  bool _loading = false;
  String _query = '';

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
          ? await AppRulesRepository.instance
              .loadInstalledAppsForChild(widget.familyId!, widget.childId!)
          : await AppRulesRepository.instance.loadInstalledApps(widget.familyId!);
      final saved = await AppRulesRepository.instance.load(widget.familyId!);
      if (!mounted) return;
      setState(() {
        _apps = reported
            .map((a) =>
                AppRule.installed(a.packageName, a.appName, owners: a.owners))
            .toList();
        for (final app in _apps) {
          final r = saved[app.packageName];
          if (r != null) {
            app.blocked = r.blocked;
            app.dailyLimitMinutes = r.dailyLimitMinutes;
            app.bankingAllowed = r.bankingAllowed;
          }
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _persist(AppRule app) {
    if (!_live) return;
    AppRulesRepository.instance.setRule(
      widget.familyId!,
      packageName: app.packageName,
      appName: app.appName,
      blocked: app.blocked,
      dailyLimitMinutes: app.dailyLimitMinutes,
      bankingAllowed: app.bankingAllowed,
    );
  }

  List<AppRule> get _filtered {
    if (_query.trim().isEmpty) return _apps;
    final q = _query.toLowerCase();
    return _apps.where((a) => a.appName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.childName == null ? 'App rules' : 'App rules · ${widget.childName}';
    final blockedCount = _apps.where((a) => a.blocked).length;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (blockedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$blockedCount app(s) blocked',
                  style: const TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apps.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'No apps yet — they appear once the child device syncs.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                            AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _AppTile(
                          app: _filtered[i],
                          onBlockChanged: (v) {
                            setState(() => _filtered[i].blocked = v);
                            _persist(_filtered[i]);
                          },
                          onBankingChanged: (v) {
                            setState(() => _filtered[i].bankingAllowed = v);
                            _persist(_filtered[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.onBlockChanged,
    required this.onBankingChanged,
  });

  final AppRule app;
  final ValueChanged<bool> onBlockChanged;
  final ValueChanged<bool> onBankingChanged;

  String? get _subtitle {
    final names = app.owners.isNotEmpty ? app.owners.join(', ') : null;
    if (app.blocked) {
      return names == null ? 'Blocked' : 'Blocked · $names';
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                  Text(app.appName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            app.blocked ? AppColors.danger : AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (app.bankingAllowed) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.account_balance_rounded,
                            size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Allowed in Secure App Mode',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'banking') onBankingChanged(!app.bankingAllowed);
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(
                  value: 'banking',
                  checked: app.bankingAllowed,
                  child: const Text('Allow in Secure App Mode'),
                ),
              ],
            ),
            Switch(value: app.blocked, onChanged: onBlockChanged),
          ],
        ),
      ),
    );
  }
}
