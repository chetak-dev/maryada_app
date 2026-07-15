import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/web_filter_repository.dart';
import '../../models/web_filter.dart';
import '../../theme/tokens.dart';

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
  bool _enabled = true;
  final _categories = demoCategories();
  final _blocked = <String>['example-badsite.com'];
  final _controller = TextEditingController();

  bool get _live => widget.familyId != null && Db.ready;

  @override
  void initState() {
    super.initState();
    if (_live) _load();
  }

  Future<void> _load() async {
    try {
      final s = await WebFilterRepository.instance.load(widget.familyId!);
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        for (final c in _categories) {
          c.blocked = s.blockedCategories.contains(c.id);
        }
        _blocked
          ..clear()
          ..addAll(s.blockedSites);
      });
    } catch (_) {
      // keep defaults
    }
  }

  void _persist() {
    if (!_live) return;
    WebFilterRepository.instance.save(
      widget.familyId!,
      WebFilterSettings(
        enabled: _enabled,
        blockedCategories:
            _categories.where((c) => c.blocked).map((c) => c.id).toSet(),
        blockedSites: List<String>.from(_blocked),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
      _persist();
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'Web filter'
        : 'Web filter · ${widget.childName}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          Card(
            color: _enabled ? AppColors.accent.withValues(alpha: 0.06) : null,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              secondary: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.accent),
              ),
              title: const Text('Safe browsing',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Filter unsafe sites and enforce SafeSearch.'),
              value: _enabled,
              onChanged: (v) {
                setState(() {
                  _enabled = v;
                  // On -> block all categories; off -> clear every category so
                  // nothing is blocked.
                  for (final c in _categories) {
                    c.blocked = v;
                  }
                });
                _persist();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Opacity(
            opacity: _enabled ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !_enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Blocked categories',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < _categories.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 64),
                          _CategoryTile(
                            category: _categories[i],
                            onChanged: (v) {
                              setState(() => _categories[i].blocked = v);
                              _persist();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                                      setState(() => _blocked.remove(site));
                                      _persist();
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
  const _CategoryTile({required this.category, required this.onChanged});
  final WebCategory category;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      secondary: Container(
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
      value: category.blocked,
      onChanged: onChanged,
    );
  }
}
