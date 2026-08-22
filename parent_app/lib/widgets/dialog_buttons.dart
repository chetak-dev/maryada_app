import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Compact, neutral secondary button for dialog "Cancel" actions — a clean
/// bordered button (not plain text), consistent across every prompt.
class DialogCancelButton extends StatelessWidget {
  const DialogCancelButton({
    super.key,
    required this.onPressed,
    this.label = 'Cancel',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondaryOf(context),
        side: BorderSide(color: AppColors.borderOf(context)),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Compact primary button for dialog confirm actions, matching
/// [DialogCancelButton]'s size so prompt buttons line up cleanly.
class DialogConfirmButton extends StatelessWidget {
  const DialogConfirmButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.color,
  });

  final VoidCallback onPressed;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
