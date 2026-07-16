import 'package:flutter/material.dart';

/// An installed app + its rule (UI model). `dailyLimitMinutes == 0` means no
/// per-app limit; `blocked` hard-blocks the app.
class AppRule {
  final String packageName;
  final String appName;
  final Color color;
  bool blocked;
  int dailyLimitMinutes;

  /// Family-wide: this app stays usable while a child has a protection turned
  /// off ("banking mode"), so strict banking/UPI apps can run. Applies to all
  /// children.
  bool bankingAllowed;

  /// Names of the children who have this app installed (family view only).
  final List<String> owners;

  AppRule({
    required this.packageName,
    required this.appName,
    required this.color,
    this.blocked = false,
    this.dailyLimitMinutes = 0,
    this.bankingAllowed = false,
    this.owners = const [],
  });

  /// Builds a rule for a real installed app, deriving a stable accent color
  /// from the package name so each app has a consistent avatar tint.
  factory AppRule.installed(
    String packageName,
    String appName, {
    List<String> owners = const [],
  }) {
    const palette = [
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF22C55E),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFD946EF),
      Color(0xFF06B6D4),
      Color(0xFF64748B),
    ];
    final color = palette[packageName.hashCode.abs() % palette.length];
    return AppRule(
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      color: color,
      owners: owners,
    );
  }

  String get initials =>
      appName.trim().isEmpty ? '?' : appName.trim()[0].toUpperCase();
}

/// Placeholder installed-apps list so the screen is explorable pre-backend.
List<AppRule> demoAppRules() => [
      AppRule(packageName: 'com.google.android.youtube', appName: 'YouTube', color: const Color(0xFFEF4444)),
      AppRule(packageName: 'com.instagram.android', appName: 'Instagram', color: const Color(0xFFD946EF)),
      AppRule(packageName: 'com.zhiliaoapp.musically', appName: 'TikTok', color: const Color(0xFF0F172A)),
      AppRule(packageName: 'com.whatsapp', appName: 'WhatsApp', color: const Color(0xFF22C55E)),
      AppRule(packageName: 'com.roblox.client', appName: 'Roblox', color: const Color(0xFF64748B)),
      AppRule(packageName: 'com.android.chrome', appName: 'Chrome', color: const Color(0xFF3B82F6)),
      AppRule(packageName: 'com.snapchat.android', appName: 'Snapchat', color: const Color(0xFFF59E0B)),
      AppRule(packageName: 'com.supercell.clashofclans', appName: 'Clash of Clans', color: const Color(0xFF8B5CF6)),
    ];
