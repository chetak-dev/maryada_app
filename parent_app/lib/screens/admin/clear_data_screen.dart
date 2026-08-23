import 'package:flutter/material.dart';

import '../../data/data_clear_repository.dart';
import '../../data/site_policy_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/dialog_buttons.dart';

enum _Range { d7, d15, d30, d60, m6, all }

/// Retention windows offered for automatic deletion; 0 keeps everything.
const _autoDeleteChoices = <(int, String)>[
  (0, 'Off — keep everything'),
  (7, 'Keep last 7 days'),
  (15, 'Keep last 15 days'),
  (30, 'Keep last 30 days'),
  (60, 'Keep last 60 days'),
  (180, 'Keep last 6 months'),
];

/// Site-admin data maintenance: wipe children's activity/history, with a
/// retention window and the option to exclude specific children. Structural
/// data (accounts, families, children, pairing, rules) is never touched.
class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});

  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen> {
  static const _ranges = <(_Range, String, int?)>[
    (_Range.d7, 'Older than 7 days', 7),
    (_Range.d15, 'Older than 15 days', 15),
    (_Range.d30, 'Older than 30 days', 30),
    (_Range.d60, 'Older than 60 days', 60),
    (_Range.m6, 'Older than 6 months', 180),
    (_Range.all, 'All data', null),
  ];

  _Range _range = _Range.d30;
  List<ChildRef> _children = const [];
  final Set<String> _excluded = {};
  bool _loading = true;
  bool _busy = false;

  String _key(ChildRef c) => '${c.familyId}/${c.childId}';
  int? _days(_Range r) => _ranges.firstWhere((e) => e.$1 == r).$3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final kids = await DataClearRepository.instance.listAllChildren();
      if (!mounted) return;
      setState(() {
        _children = kids;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ChildRef> get _included =>
      _children.where((c) => !_excluded.contains(_key(c))).toList();

  Future<void> _clear() async {
    final included = _included;
    if (included.isEmpty) return;
    final isAll = _range == _Range.all;
    final rangeLabel = _ranges.firstWhere((e) => e.$1 == _range).$2.toLowerCase();

    final confirmed = await _confirm(included.length, isAll, rangeLabel);
    if (confirmed != true) return;

    setState(() => _busy = true);
    final days = _days(_range);
    final cutoff = days == null ? null : DateTime.now().subtract(Duration(days: days));
    try {
      await DataClearRepository.instance
          .clearActivity(children: included, cutoff: cutoff);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Cleared activity for ${included.length} child(ren).')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t clear the data — ${friendlyError(e)}')),
      );
    }
  }

  Future<bool?> _confirm(int count, bool isAll, String rangeLabel) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final canClear = !isAll || controller.text.trim().toUpperCase() == 'CLEAR';
          return AlertDialog(
            title: Text(isAll ? 'Delete ALL activity?' : 'Clear activity?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAll
                    ? 'This permanently deletes ALL activity/history for '
                        '$count child(ren) — web, calls, SMS, chat, YouTube, '
                        'location, usage and alerts. Devices stay paired. This '
                        'cannot be undone.'
                    : 'This permanently deletes activity $rangeLabel for '
                        '$count child(ren). This cannot be undone.'),
                if (isAll) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text('Type CLEAR to confirm:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'CLEAR'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ],
            ),
            actions: [
              DialogCancelButton(onPressed: () => Navigator.pop(ctx, false)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: canClear ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Clear'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clear activity data')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border:
                        Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning, size: 20),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Deletes activity/history only (web, calls, SMS, chat, '
                          'YouTube, location, usage, alerts). Devices stay paired '
                          'and keep monitoring. This can’t be undone.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Auto-delete',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Activity older than the window is deleted automatically, '
                  'once a day, for every child.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                const _AutoDeleteCard(),
                const SizedBox(height: AppSpacing.lg),
                Text('Delete records now',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (final r in _ranges)
                        ListTile(
                          onTap:
                              _busy ? null : () => setState(() => _range = r.$1),
                          title: Text(r.$2),
                          dense: true,
                          trailing: Icon(
                            _range == r.$1
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: _range == r.$1
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Children (${_included.length}/${_children.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    TextButton(
                      onPressed: _busy || _children.isEmpty
                          ? null
                          : () => setState(() {
                                if (_excluded.isEmpty) {
                                  _excluded.addAll(_children.map(_key));
                                } else {
                                  _excluded.clear();
                                }
                              }),
                      child: Text(_excluded.isEmpty ? 'None' : 'All'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_children.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text('No paired children yet.',
                          style: TextStyle(
                              color: AppColors.textSecondaryOf(context))),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final c in _children)
                          CheckboxListTile(
                            value: !_excluded.contains(_key(c)),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      if (v == true) {
                                        _excluded.remove(_key(c));
                                      } else {
                                        _excluded.add(_key(c));
                                      }
                                    }),
                            title: Text(c.name),
                            subtitle: c.ownerEmail.isEmpty
                                ? null
                                : Text(c.ownerEmail),
                            dense: true,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: (_busy || _included.isEmpty) ? null : _clear,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_sweep_rounded),
                  label: Text(_busy ? 'Clearing…' : 'Clear data'),
                ),
              ],
            ),
    );
  }
}

/// The retention window, saved the moment it is picked.
class _AutoDeleteCard extends StatelessWidget {
  const _AutoDeleteCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RetentionPolicy>(
      stream: SitePolicyRepository.instance.watchRetention(),
      builder: (context, snap) {
        final policy = snap.data ?? const RetentionPolicy();
        final known =
            _autoDeleteChoices.any((c) => c.$1 == policy.days);
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_delete_rounded,
                        color: policy.enabled
                            ? AppColors.primary
                            : AppColors.textMuted),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text('Keep activity for',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    DropdownButton<int>(
                      value: known ? policy.days : 0,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      items: [
                        for (final (days, label) in _autoDeleteChoices)
                          DropdownMenuItem(value: days, child: Text(label)),
                      ],
                      onChanged: (days) async {
                        if (days == null) return;
                        try {
                          await SitePolicyRepository.instance
                              .setRetentionDays(days);
                        } catch (e) {
                          if (context.mounted) {
                            context.showError('Couldn’t save the window', e);
                          }
                        }
                      },
                    ),
                  ],
                ),
                if (policy.enabled && policy.lastRunAt != null)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 40, bottom: AppSpacing.xs),
                    child: Text(
                      'Last run ${_ago(policy.lastRunAt!)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
