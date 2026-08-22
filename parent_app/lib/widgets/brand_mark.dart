import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The Maryada mark. Reusable across the login, splash and app bar; [size]
/// controls the whole mark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: showGlow
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.10),
                ),
              ],
            )
          : null,
      child: Image.asset('assets/logo.png',
          width: size, height: size, semanticLabel: 'Maryada'),
    );
  }
}

/// Brand wordmark "Maryada" with the shield badge — used on auth screens.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.markSize = 40});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize, showGlow: false),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Maryada',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
      ],
    );
  }
}

/// Full-screen branded loading view.
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A plain surface, not the brand gradient: the mark is a dark shield and it
    // sank into the purple.
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 132, showGlow: false),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Maryada',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 132,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
