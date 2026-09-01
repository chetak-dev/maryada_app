import 'package:flutter/material.dart';

import '../../data/family_repository.dart';
import '../../data/tags_repository.dart';
import '../../models/tag.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/net_guard.dart';

/// Creates a profile on its own — no pairing code involved. Devices are added
/// from inside the profile afterwards.
Future<void> showNewProfileDialog(
    BuildContext context, String familyId) async {
  final messenger = ScaffoldMessenger.of(context);
  // Offered at creation so a new profile lands in the right group straight
  // away. Never block making a profile because the tags couldn't be read.
  List<FamilyTag> tags;
  try {
    tags = await TagsRepository.instance.load(familyId);
  } catch (_) {
    tags = const [];
  }
  if (!context.mounted) return;
  final controller = TextEditingController();
  // Explicit focus a frame after the dialog builds: `autofocus` alone opens
  // the keyboard without a working input connection on some OEM keyboards.
  final focus = FocusNode();
  WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  final chosen = <String>{};
  final result = await showDialog<({String name, List<String> tagIds})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final typed = controller.text.trim();
        // A group is required once the admin has defined any, so no profile
        // can be created outside the family's grouping.
        final ready = typed.isNotEmpty && (tags.isEmpty || chosen.isNotEmpty);

        void submit() {
          if (!ready) return;
          Navigator.pop(ctx, (name: typed, tagIds: chosen.toList()));
        }

        return AlertDialog(
          title: const Text('New profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  focusNode: focus,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Child\u2019s name',
                    hintText: 'e.g. Aarav',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Group',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // A profile belongs to exactly one group, so picking a
                  // second replaces the first.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tags)
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          avatar: CircleAvatar(
                            backgroundColor: t.color,
                            radius: 6,
                          ),
                          label: Text(t.name),
                          selected: chosen.contains(t.id),
                          onSelected: (on) => setState(() {
                            chosen.clear();
                            if (on) chosen.add(t.id);
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
            DialogConfirmButton(
              onPressed: ready ? submit : null,
              label: 'Create',
            ),
          ],
        );
      },
    ),
  );
  focus.dispose();
  if (result == null || result.name.isEmpty) return;
  final name = result.name;
  if (!context.mounted) return;
  if (!await Net.require(context)) return;
  if (!context.mounted) return;
  try {
    await Net.withProgress(
      context,
      'Creating $name\u2019s profile…',
      () => FamilyRepository.instance.addChild(
        familyId: familyId,
        name: name,
        avatarColor: AppColors.avatarFor(name).toARGB32(),
        tagIds: result.tagIds,
      ),
    );
    messenger.showSnackBar(SnackBar(
        content:
            Text('$name\u2019s profile is ready. Open it to add a device.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content:
            Text('Couldn\u2019t create the profile — ${friendlyError(e)}')));
  }
}
