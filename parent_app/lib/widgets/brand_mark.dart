import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The GuardNest brand mark: a rounded, gradient shield badge. Reusable across
/// the login, splash and app bar. Size controls the whole badge.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: size * 0.4,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.shield_rounded,
        color: Colors.white,
        size: size * 0.56,
      ),
    );
  }
}

/// Brand wordmark "GuardNest" with the shield badge — used on auth screens.
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

/// Full-screen branded loading view. Matches the HTML boot splash in
/// `web/index.html` so the app's initial loading looks like a single, seamless
/// loader instead of two different spinners.
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Maryada',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
