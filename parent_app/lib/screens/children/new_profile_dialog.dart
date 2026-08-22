import 'package:flutter/material.dart';

import '../../data/family_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/feedback.dart';
import '../../widgets/dialog_buttons.dart';
import '../../widgets/net_guard.dart';

/// Creates a profile on its own — no pairing code involved. Devices are added
/// from inside the profile afterwards.
Future<void> showNewProfileDialog(
    BuildContext context, String familyId) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();
  // Explicit focus a frame after the dialog builds: `autofocus` alone opens
  // the keyboard without a working input connection on some OEM keyboards.
  final focus = FocusNode();
  WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New profile'),
      content: TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Child’s name',
          hintText: 'e.g. Aarav',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        DialogCancelButton(onPressed: () => Navigator.pop(ctx)),
        DialogConfirmButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          label: 'Create',
        ),
      ],
    ),
  );
  focus.dispose();
  if (name == null || name.isEmpty) return;
  if (!context.mounted) return;
  if (!await Net.require(context)) return;
  if (!context.mounted) return;
  try {
    await Net.withProgress(
      context,
      'Creating $name’s profile…',
      () => FamilyRepository.instance.addChild(
        familyId: familyId,
        name: name,
        avatarColor: AppColors.avatarFor(name).toARGB32(),
      ),
    );
    messenger.showSnackBar(SnackBar(
        content:
            Text('$name’s profile is ready. Open it to add a device.')));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Couldn’t create the profile — ${friendlyError(e)}')));
  }
}
