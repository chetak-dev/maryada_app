import 'package:flutter/material.dart';

import '../../data/builtin_keywords.dart';
import '../../data/site_policy_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/feedback.dart';

/// Site-admin view of every word that blocks a page, grouped by category: the
/// lists built into the child app plus the words admins added. The added words
/// can be edited or removed; the built-in lists ship with the child app and are
/// read-only here.
class ContentKeywordsScreen extends StatefulWidget {
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
  State<ContentKeywordsScreen> createState() => _ContentKeywordsScreenState();
}

class _ContentKeywordsScreenState extends State<ContentKeywordsScreen> {
  final _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

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
              TextField(
                controller: _searchCtl,
                textInputAction: TextInputAction.search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search every keyword',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final c in ContentKeywordsScreen._categories)
                _CategoryTile(
                  category: c,
                  keywords: byCat[c.id] ?? const [],
                  query: _query,
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
              'A page is blocked on every child device when its visible text '
              'matches one of these words. Words you add can be edited or '
              'removed; the built-in lists ship with the child app.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// One category row. Opens its own page — an expanding tile kept collapsing
/// itself every time the Firestore stream pushed a new snapshot, so the words
/// were never on screen long enough to read.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.keywords,
    required this.query,
  });

  final _KwCategory category;
  final List<String> keywords;
  final String query;

  List<String> _filter(List<String> words) => query.isEmpty
      ? words
      : words.where((w) => w.contains(query)).toList();

  @override
  Widget build(BuildContext context) {
    final c = category;
    final hits = _filter(kBuiltinStrongKeywords[c.id] ?? const []).length +
        _filter(kBuiltinWeakKeywords[c.id] ?? const []).length +
        _filter(keywords).length;
    if (query.isNotEmpty && hits == 0) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(c.icon, color: c.color, size: 22),
        ),
        title:
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          query.isNotEmpty
              ? '$hits match${hits == 1 ? '' : 'es'}'
              : '${builtinCount(c.id)} built-in · ${keywords.length} added',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _CategoryPage(category: c, query: query),
          ),
        ),
      ),
    );
  }
}

/// Every word that blocks in one category, plus the box to add another.
class _CategoryPage extends StatefulWidget {
  const _CategoryPage({required this.category, required this.query});

  final _KwCategory category;
  final String query;

  @override
  State<_CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<_CategoryPage> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _filter(List<String> words) => widget.query.isEmpty
      ? words
      : words.where((w) => w.contains(widget.query)).toList();

  /// Everything already blocking here, so the same word can't be added twice.
  Set<String> _existing(List<String> mine) => {
        ...mine,
        ...?kBuiltinStrongKeywords[widget.category.id],
        ...?kBuiltinWeakKeywords[widget.category.id],
      };

  Future<void> _add(List<String> all) async {
    final word = _controller.text.trim().toLowerCase();
    final messenger = ScaffoldMessenger.of(context);
    if (word.length < 3) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Use at least 3 characters.')),
      );
      return;
    }
    if (_existing(all).contains(word)) {
      _controller.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('"$word" already blocks in this category.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SitePolicyRepository.instance
          .setCategoryKeywords(widget.category.id, [word, ...all]);
      _controller.clear();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text('Couldn\'t add that keyword: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Removing a keyword unblocks it on every child device, so it is confirmed.
  Future<void> _remove(String word, List<String> all) async {
    final messenger = ScaffoldMessenger.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove keyword?'),
        content: Text(
          '"$word" will stop blocking pages on every child device.',
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Remove',
            color: AppColors.danger,
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await SitePolicyRepository.instance.setCategoryKeywords(
        widget.category.id,
        [...all]..remove(word),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t remove it: ${friendlyError(e)}')),
      );
    }
  }

  Future<void> _edit(String word, List<String> all) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctl = TextEditingController(text: word);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit keyword'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Keyword'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().toLowerCase()),
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
          DialogConfirmButton(
            onPressed: () =>
                Navigator.pop(ctx, ctl.text.trim().toLowerCase()),
            label: 'Save',
          ),
        ],
      ),
    );
    ctl.dispose();
    if (next == null || next == word) return;
    if (next.length < 3) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Use at least 3 characters.')),
      );
      return;
    }
    if (_existing(all).contains(next)) {
      messenger.showSnackBar(
        SnackBar(content: Text('"$next" already blocks in this category.')),
      );
      return;
    }
    try {
      await SitePolicyRepository.instance.setCategoryKeywords(
        widget.category.id,
        [for (final w in all) if (w == word) next else w],
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t save it: ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final strong = _filter(kBuiltinStrongKeywords[c.id] ?? const []);
    final weak = _filter(kBuiltinWeakKeywords[c.id] ?? const []);
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: StreamBuilder<Map<String, List<String>>>(
        stream: SitePolicyRepository.instance.watchCategoryKeywords(),
        builder: (context, snap) {
          // Writes are built from the WHOLE list; the filtered copy is only
          // for display. Editing off the filtered list would silently drop
          // every word the search box happened to be hiding.
          final all = (snap.data ?? const {})[c.id] ?? const <String>[];
          final mine = _filter(all);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _add(all),
                      decoration: const InputDecoration(
                        hintText: 'Add a keyword',
                        prefixIcon: Icon(Icons.text_fields_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _saving ? null : () => _add(all),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (mine.isNotEmpty)
                _KeywordGroup(
                  title: 'Added by admins',
                  caption: 'Blocks the page on a single match. '
                      'Tap to edit, or use the cross to remove.',
                  words: mine,
                  onEdit: (w) => _edit(w, all),
                  onRemove: (w) => _remove(w, all),
                ),
              if (strong.isNotEmpty)
                _KeywordGroup(
                  title: 'Built-in · always blocks',
                  caption: 'One match anywhere on the page blocks it.',
                  words: strong,
                ),
              if (weak.isNotEmpty)
                _KeywordGroup(
                  title: 'Built-in · blocks on repeat',
                  caption: 'Everyday words — several different matches on the '
                      'same page are needed, so ordinary pages stay open.',
                  words: weak,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KeywordGroup extends StatelessWidget {
  const _KeywordGroup({
    required this.title,
    required this.caption,
    required this.words,
    this.onEdit,
    this.onRemove,
  });

  final String title;
  final String caption;
  final List<String> words;

  /// Both null for the built-in lists, which ship with the child app and so
  /// cannot be changed from here.
  final ValueChanged<String>? onEdit;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final editable = onEdit != null && onRemove != null;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · ${words.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(caption,
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          if (editable)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in words)
                  InputChip(
                    label: Text(w),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onEdit!(w),
                    onDeleted: () => onRemove!(w),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  ),
              ],
            )
          else
            // Plain comma-separated text: chips at this volume rendered poorly
            // and the built-in lists are read-only anyway.
            SelectableText(
              words.join(', '),
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
        ],
      ),
    );
  }
}
