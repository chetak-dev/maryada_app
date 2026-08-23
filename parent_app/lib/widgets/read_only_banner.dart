import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small banner shown on editor screens for accounts whose changes are
/// turned off, so they understand why controls don't respond. Deliberately
/// doesn't name the account's access level.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Changes are managed by your administrator — this screen is for '
              'viewing.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
