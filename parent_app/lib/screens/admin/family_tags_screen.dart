import 'package:flutter/material.dart';

import '../../data/tags_repository.dart';
import '../../models/tag.dart';
import '../../theme/tokens.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/feedback.dart';

/// Site-admin management of one family's tags.
///
/// The admin owns the vocabulary so a group means the same thing to every
/// guardian in the household; assigning a tag to a profile is the guardian's
/// job and lives on the profile itself.
class FamilyTagsScreen extends StatelessWidget {
  const FamilyTagsScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  final String familyId;
  final String familyName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tags · $familyName')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New tag'),
      ),
      body: StreamBuilder<List<FamilyTag>>(
        stream: TagsRepository.instance.watch(familyId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tags = snap.data ?? const <FamilyTag>[];
          if (tags.isEmpty) {
            return const EmptyState(
              icon: Icons.sell_outlined,
              title: 'No tags yet',
              message:
                  'Create tags like "Class 8" or "Hostel", then guardians can '
                  'put them on their profiles and filter the list by group.',
              color: AppColors.primary,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            itemCount: tags.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _TagRow(
              tag: tags[i],
              familyId: familyId,
              onEdit: () => _edit(context, tags[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, FamilyTag? existing) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String name, int color})>(
      context: context,
      builder: (ctx) => _TagDialog(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await TagsRepository.instance.create(
          familyId,
          result.name,
          result.color,
        );
      } else {
        await TagsRepository.instance.rename(
          familyId,
          existing.id,
          result.name,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\u2019t save the tag — ${friendlyError(e)}')),
      );
    }
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.familyId,
    required this.onEdit,
  });

  final FamilyTag tag;
  final String familyId;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              tag.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Rename',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _delete(context),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // Say how many profiles lose the tag: deleting a group of twenty is a very
    // different act from deleting an unused one.
    int used = 0;
    try {
      used = await TagsRepository.instance.usageCount(familyId, tag.id);
    } catch (_) {}
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text(
          used == 0
              ? '"${tag.name}" is not on any profile.'
              : '"${tag.name}" will be removed from $used profile'
                    '${used == 1 ? '' : 's'}. Their data is not affected.',
        ),
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(ctx, false)),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Delete',
            color: AppColors.danger,
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TagsRepository.instance.delete(familyId, tag.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Couldn\u2019t delete the tag — ${friendlyError(e)}'),
        ),
      );
    }
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({this.existing});
  final FamilyTag? existing;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.color.toARGB32() ?? tagPalette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New tag' : 'Rename tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tag name',
              hintText: 'Class 8',
            ),
          ),
          if (widget.existing == null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final c in tagPalette)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c
                              ? AppColors.textPrimaryOf(context)
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        DialogCancelButton(onPressed: () => Navigator.pop(context)),
        DialogConfirmButton(
          onPressed: () => Navigator.pop(
            context,
            (name: _name.text.trim(), color: _color),
          ),
          label: 'Save',
        ),
      ],
    );
  }
}
