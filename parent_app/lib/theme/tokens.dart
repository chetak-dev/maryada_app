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

  /// Avatar fills, picked from a name so one contact keeps the same colour
  /// everywhere instead of every avatar being the same grey circle.
  static const List<Color> avatarPalette = [
    Color(0xFF4338CA), // indigo
    Color(0xFF0891B2), // cyan
    Color(0xFF16A34A), // green
    Color(0xFFCA8A04), // gold
    Color(0xFFDB2777), // pink
    Color(0xFF7C3AED), // violet
    Color(0xFFEA580C), // orange
    Color(0xFF0D9488), // teal
  ];

  static Color avatarFor(String seed) {
    if (seed.isEmpty) return avatarPalette.first;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return avatarPalette[hash % avatarPalette.length];
  }

  // Brightness-aware helpers. Widgets that paint their own containers must
  // use these instead of the raw light tokens, or dark mode shows white
  // cards on a near-black background.
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surfaceOf(BuildContext context) =>
      _dark(context) ? surfaceDark : surface;
  static Color surfaceMutedOf(BuildContext context) =>
      _dark(context) ? surfaceMutedDark : surfaceMuted;
  static Color borderOf(BuildContext context) =>
      _dark(context) ? borderDark : border;
  static Color textPrimaryOf(BuildContext context) =>
      _dark(context) ? textOnDark : textPrimary;
  static Color textSecondaryOf(BuildContext context) =>
      _dark(context) ? textSecondaryOnDark : textSecondary;
}

/// Palette for the captured-conversation view only.
///
/// Deliberately outside [AppColors]: these values mirror the messaging app the
/// conversation was captured from, so a parent reads it in the shape they
/// already know. Don't use them anywhere else in the app.
class ChatColors {
  ChatColors._();

  static const Color wallpaper = Color(0xFFEFEAE2);
  static const Color incoming = Color(0xFFFFFFFF);
  static const Color outgoing = Color(0xFFD9FDD3);
  static const Color text = Color(0xFF111B21);
  static const Color meta = Color(0xFF667781);
  // The header is a plain surface with a bold title — the green toolbar was
  // retired from the app years ago.
  static const Color header = Color(0xFFFFFFFF);
  static const Color headerText = Color(0xFF111B21);
  static const Color dateChip = Color(0xFFFFFFFF);

  static const Color wallpaperDark = Color(0xFF0B141A);
  static const Color incomingDark = Color(0xFF1F2C34);
  static const Color outgoingDark = Color(0xFF005C4B);
  static const Color textDark = Color(0xFFE9EDEF);
  static const Color metaDark = Color(0xFF8696A0);
  static const Color headerDark = Color(0xFF0B141A);
  static const Color headerTextDark = Color(0xFFE9EDEF);
  static const Color dateChipDark = Color(0xFF182229);

  // Conversation list
  static const Color listBg = Color(0xFFFFFFFF);
  static const Color listBgDark = Color(0xFF111B21);
  static const Color divider = Color(0xFFE9EDEF);
  static const Color dividerDark = Color(0xFF222D34);
  static const Color searchFill = Color(0xFFF0F2F5);
  static const Color searchFillDark = Color(0xFF202C33);
  static const Color avatarBg = Color(0xFFDFE5E7);
  static const Color avatarBgDark = Color(0xFF6A7175);

  // The blue "read" double tick shown on sent messages (same in both themes).
  static const Color tick = Color(0xFF53BDEB);

  // The pale-yellow notice banner pinned at the top of a conversation.
  static const Color notice = Color(0xFFFDF3C5);
  static const Color noticeText = Color(0xFF54656F);
  static const Color noticeDark = Color(0xFF182229);
  static const Color noticeTextDark = Color(0xFFFFD279);

  // The faint doodle drawn over the wallpaper.
  static const Color doodle = Color(0x1454656F);
  static const Color doodleDark = Color(0x10E9EDEF);

  static Color wallpaperOf(bool dark) => dark ? wallpaperDark : wallpaper;
  static Color incomingOf(bool dark) => dark ? incomingDark : incoming;
  static Color outgoingOf(bool dark) => dark ? outgoingDark : outgoing;
  static Color textOf(bool dark) => dark ? textDark : text;
  static Color metaOf(bool dark) => dark ? metaDark : meta;
  static Color headerOf(bool dark) => dark ? headerDark : header;
  static Color headerTextOf(bool dark) => dark ? headerTextDark : headerText;
  static Color dateChipOf(bool dark) => dark ? dateChipDark : dateChip;
  static Color listBgOf(bool dark) => dark ? listBgDark : listBg;
  static Color dividerOf(bool dark) => dark ? dividerDark : divider;
  static Color searchFillOf(bool dark) => dark ? searchFillDark : searchFill;
  static Color avatarBgOf(bool dark) => dark ? avatarBgDark : avatarBg;
  static Color noticeOf(bool dark) => dark ? noticeDark : notice;
  static Color noticeTextOf(bool dark) => dark ? noticeTextDark : noticeText;
  static Color doodleOf(bool dark) => dark ? doodleDark : doodle;
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
