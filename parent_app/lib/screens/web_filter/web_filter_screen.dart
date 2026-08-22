import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/site_policy_repository.dart';
import '../../data/web_filter_repository.dart';
import '../../models/web_filter.dart';
import '../../theme/tokens.dart';
import '../../widgets/access_scope.dart';
import '../../widgets/feedback.dart';
import '../../widgets/read_only_banner.dart';

/// Web filter editor: master safe-browsing switch, content-category toggles and
/// a custom blocklist. Persists to Firestore when [familyId] is set.
class WebFilterScreen extends StatefulWidget {
  const WebFilterScreen({super.key, this.childName, this.familyId});

  final String? childName;
  final String? familyId;

  @override
  State<WebFilterScreen> createState() => _WebFilterScreenState();
}

class _WebFilterScreenState extends State<WebFilterScreen> {
  // Safe browsing can't be switched off by anyone, so this is a constant — it
  // is kept as a field only because the layout below reads it.
  static const bool _enabled = true;
  final _categories = demoCategories();
  final _blocked = <String>[];
  final _controller = TextEditingController();
  bool _canEdit = true;
  StreamSubscription<WebPolicy>? _policySub;

  bool get _live => widget.familyId != null && Db.ready;

  @override
  void initState() {
    super.initState();
    _policySub = SitePolicyRepository.instance.watchPolicy().listen((p) {
      if (!mounted) return;
      setState(() {
        for (final c in _categories) {
          c.blocked = p.blockedCategories.contains(c.id);
        }
      });
    });
    if (_live) _load();
  }

  Future<void> _load() async {
    try {
      final s = await WebFilterRepository.instance.load(widget.familyId!);
      if (!mounted) return;
      setState(() {
        _blocked
          ..clear()
          ..addAll(s.blockedSites);
      });
    } catch (e) {
      // Showing an empty list as if it were the saved one would tell the parent
      // nothing is blocked, so say the list couldn't be read.
      if (mounted) context.showError('Couldn’t load the blocklist', e);
    }
  }

  /// Saves the blocklist, undoing [revert] if the write is rejected so the
  /// chips on screen always reflect what the child device will actually get.
  Future<void> _persist(VoidCallback revert) async {
    if (!_live || !_canEdit) return;
    try {
      await WebFilterRepository.instance.save(
        widget.familyId!,
        WebFilterSettings(
          enabled: _enabled,
          blockedSites: List<String>.from(_blocked),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(revert);
      context.showError('Couldn’t save the blocklist', e);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _policySub?.cancel();
    super.dispose();
  }

  void _addSite() {
    final raw = _controller.text.trim().toLowerCase();
    if (raw.isEmpty) return;
    final host = raw
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst('www.', '')
        .split('/')
        .first;
    if (host.isEmpty || !host.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid website, e.g. site.com')),
      );
      return;
    }
    if (!_blocked.contains(host)) {
      setState(() => _blocked.insert(0, host));
      _persist(() => _blocked.remove(host));
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    _canEdit = AccessScope.of(context);
    final title = widget.childName == null
        ? 'Web filter'
        : 'Web filter · ${widget.childName}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          if (!_canEdit) const ReadOnlyBanner(),
          Card(
            color: _enabled ? AppColors.success.withValues(alpha: 0.06) : null,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.success),
              ),
              title: const Text('Safe browsing',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Always on · cannot be turned off'),
              trailing: const Icon(Icons.lock_outline_rounded,
                  color: AppColors.textMuted, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: (_enabled ? AppColors.success : AppColors.danger)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  _enabled
                      ? Icons.verified_user_rounded
                      : Icons.gpp_bad_rounded,
                  color: _enabled ? AppColors.success : AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _enabled
                        ? 'On — your child is protected. Unsafe sites are blocked.'
                        : 'Off — no websites are blocked. Your child can visit any site.',
                    style: TextStyle(
                      color: _enabled ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Blocked categories are managed globally by the site admin — shown
          // read-only so an org admin can't turn any protection off.
          Text('Blocked categories',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Managed by your administrator.',
              style: TextStyle(
                  color: AppColors.textSecondaryOf(context), fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          Opacity(
            opacity: _enabled ? 1 : 0.5,
            child: Card(
              child: Column(
                children: [
                  for (var i = 0; i < _categories.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 64),
                    _CategoryTile(category: _categories[i]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Custom blocklist — org admins may add their own sites (this only
          // adds protection, never removes it).
          Opacity(
            opacity: (_enabled && _canEdit) ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !_enabled || !_canEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Custom blocklist',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  keyboardType: TextInputType.url,
                                  onSubmitted: (_) => _addSite(),
                                  decoration: const InputDecoration(
                                    hintText: 'Add a website (e.g. site.com)',
                                    prefixIcon: Icon(Icons.link_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              IconButton.filled(
                                onPressed: _addSite,
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                          if (_blocked.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final site in _blocked)
                                  Chip(
                                    label: Text(site),
                                    onDeleted: () {
                                      final at = _blocked.indexOf(site);
                                      setState(() => _blocked.remove(site));
                                      _persist(() => _blocked.insert(at, site));
                                    },
                                    deleteIcon:
                                        const Icon(Icons.close, size: 16),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final WebCategory category;

  @override
  Widget build(BuildContext context) {
    final blocked = category.blocked;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: category.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(category.icon, color: category.color, size: 22),
      ),
      title: Text(category.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(category.description),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (blocked ? AppColors.danger : AppColors.textMuted)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          blocked ? 'Blocked' : 'Allowed',
          style: TextStyle(
            color: blocked ? AppColors.danger : AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
