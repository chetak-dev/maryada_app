import 'package:flutter/material.dart';

import '../../data/site_policy_repository.dart';
import '../../theme/tokens.dart';

/// Site-admin editor for the content-blocking keyword lists, grouped by
/// category. Keywords added here block on every child device (on top of the
/// built-in lists) — pages whose visible text contains a keyword are blocked.
class ContentKeywordsScreen extends StatelessWidget {
  const ContentKeywordsScreen({super.key});

  static const _categories = <_KwCategory>[
    _KwCategory('adult', 'Adult content', Icons.no_adult_content,
        Color(0xFFEF4444)),
    _KwCategory('gambling', 'Gambling & betting', Icons.casino_rounded,
        Color(0xFFF59E0B)),
    _KwCategory('drugs', 'Drugs & alcohol', Icons.medication_liquid_rounded,
        Color(0xFF8B5CF6)),
    _KwCategory('weapons', 'Weapons', Icons.gpp_bad_rounded, Color(0xFF64748B)),
    _KwCategory('violence', 'Violence & self-harm', Icons.warning_amber_rounded,
        Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content keywords')),
      body: StreamBuilder<Map<String, List<String>>>(
        stream: SitePolicyRepository.instance.watchCategoryKeywords(),
        builder: (context, snap) {
          final byCat = snap.data ?? const <String, List<String>>{};
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
            children: [
              const _InfoBanner(),
              const SizedBox(height: AppSpacing.md),
              for (final c in _categories)
                _CategoryCard(
                  category: c,
                  keywords: byCat[c.id] ?? const [],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KwCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  const _KwCategory(this.id, this.name, this.icon, this.color);
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'These keywords block on every child device, in addition to the '
              'built-in lists. A page is blocked when its visible text contains '
              'a keyword.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.category, required this.keywords});
  final _KwCategory category;
  final List<String> keywords;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final word = _controller.text.trim().toLowerCase();
    if (word.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use at least 3 characters.')),
      );
      return;
    }
    if (widget.keywords.contains(word)) {
      _controller.clear();
      return;
    }
    setState(() => _saving = true);
    try {
      await SitePolicyRepository.instance
          .setCategoryKeywords(widget.category.id, [word, ...widget.keywords]);
      _controller.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String word) {
    return SitePolicyRepository.instance.setCategoryKeywords(
      widget.category.id,
      widget.keywords.where((w) => w != word).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(c.icon, color: c.color, size: 22),
          ),
          title: Text(c.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            widget.keywords.isEmpty
                ? 'No custom keywords'
                : '${widget.keywords.length} keyword(s)',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      hintText: 'Add a keyword to ${c.name.toLowerCase()}',
                      prefixIcon: const Icon(Icons.text_fields_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _saving ? null : _add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (widget.keywords.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final w in widget.keywords)
                    Chip(
                      label: Text(w),
                      onDeleted: () => _remove(w),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
