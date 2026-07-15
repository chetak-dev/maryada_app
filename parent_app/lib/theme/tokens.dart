import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for colour, spacing, radius and
/// elevation. Never hardcode these values in widgets; reference the tokens so
/// the whole app stays visually consistent and easy to re-theme.
class AppColors {
  AppColors._();

  // Brand — a calm, trustworthy indigo with an emerald "safe" accent.
  static const Color primary = Color(0xFF4F46E5); // indigo 600
  static const Color primaryDark = Color(0xFF3730A3); // indigo 800
  static const Color primaryLight = Color(0xFFEEF2FF); // indigo 50

  static const Color accent = Color(0xFF10B981); // emerald 500 (safe / online)
  static const Color accentDark = Color(0xFF047857);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF06B6D4);

  // Light surfaces
  static const Color background = Color(0xFFF7F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F3F9);
  static const Color border = Color(0xFFE2E8F0);

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF0B1020);
  static const Color surfaceDark = Color(0xFF151B2E);
  static const Color surfaceMutedDark = Color(0xFF1E2740);
  static const Color borderDark = Color(0xFF2A3352);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnDark = Color(0xFFF8FAFC);
  static const Color textSecondaryOnDark = Color(0xFF94A3B8);

  // Brand gradient (headers, hero, logo mark)
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5), Color(0xFF7C3AED)],
  );
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}
