import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A destructive confirmation that can't be tapped through: the exact name has
/// to be typed before the action button turns on.
///
/// Used for anything that can't be undone — deleting a profile, removing a
/// device, revoking a parent's access.
class TypedDangerDialog extends StatefulWidget {
  const TypedDangerDialog({
    super.key,
    required this.title,
    required this.warning,
    required this.prompt,
    required this.expected,
    required this.actionLabel,
  });

  final String title;
  final String warning;
  final String prompt;

  /// What the user must type, matched case-insensitively.
  final String expected;
  final String actionLabel;

  @override
  State<TypedDangerDialog> createState() => _TypedDangerDialogState();
}

class _TypedDangerDialogState extends State<TypedDangerDialog> {
  final _controller = TextEditingController();

  bool get _matches =>
      _controller.text.trim().toLowerCase() ==
          widget.expected.trim().toLowerCase() &&
      widget.expected.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gpp_maybe_rounded,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.warning,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(widget.prompt, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.expected,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondaryOf(context),
                  side: BorderSide(color: AppColors.borderOf(context)),
                ),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', maxLines: 1),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger),
                onPressed: _matches ? () => Navigator.pop(context, true) : null,
                // One line always: a wrapped label made the two buttons
                // different heights and the dialog look broken.
                child: Text(widget.actionLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
