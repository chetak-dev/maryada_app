import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for colour, spacing, radius and
/// elevation. Never hardcode these values in widgets; reference the tokens so
/// the whole app stays visually consistent and easy to re-theme.
class AppColors {
  AppColors._();

  // Brand — "Royal & Warm": a dignified royal indigo paired with a warm gold.
  static const Color primary = Color(0xFF4338CA); // royal indigo
  static const Color primaryDark = Color(0xFF312E81); // indigo 900
  static const Color primaryLight = Color(0xFFECEBFB); // soft indigo tint

  static const Color accent = Color(0xFFCA8A04); // warm gold (premium highlight)
  static const Color accentDark = Color(0xFFA16207);
  static const Color accentLight = Color(0xFFFBF1D6); // gold tint

  // Status (semantic, distinct from the gold accent)
  static const Color success = Color(0xFF16A34A); // green (safe / online)
  static const Color warning = Color(0xFFEA580C); // orange
  static const Color danger = Color(0xFFDC2626); // red
  static const Color info = Color(0xFF0891B2); // cyan

  // Light surfaces — warm off-white / cream
  static const Color background = Color(0xFFFBF9F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4F1EC);
  static const Color border = Color(0xFFEAE6DF);

  // Dark surfaces — deep royal night
  static const Color backgroundDark = Color(0xFF141220);
  static const Color surfaceDark = Color(0xFF1E1B2E);
  static const Color surfaceMutedDark = Color(0xFF2A2540);
  static const Color borderDark = Color(0xFF383152);

  // Text — warm neutral (stone)
  static const Color textPrimary = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF57534E);
  static const Color textMuted = Color(0xFFA8A29E);
  static const Color textOnDark = Color(0xFFF5F3F0);
  static const Color textSecondaryOnDark = Color(0xFFA8A29E);

  // Brand gradient (headers, hero, logo mark) — royal indigo -> violet
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF6D28D9), Color(0xFF7C3AED)],
  );
}

/// Soft, warm elevation shadows — used instead of hard borders for a premium feel.
class AppShadow {
  AppShadow._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F1C1917),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x0A1C1917),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x1A4338CA),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];
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
