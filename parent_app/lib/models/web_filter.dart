import 'package:flutter/material.dart';

/// A content category the web filter can block.
class WebCategory {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  bool blocked;

  WebCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    this.blocked = false,
  });
}

List<WebCategory> demoCategories() => [
      WebCategory(
        id: 'adult',
        name: 'Adult content',
        description: 'Pornography and explicit material',
        icon: Icons.no_adult_content,
        color: const Color(0xFFEF4444),
        blocked: true,
      ),
      WebCategory(
        id: 'gambling',
        name: 'Gambling',
        description: 'Betting and casino sites',
        icon: Icons.casino_rounded,
        color: const Color(0xFFF59E0B),
        blocked: true,
      ),
      WebCategory(
        id: 'violence',
        name: 'Violence & gore',
        description: 'Graphic or violent content',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFDC2626),
        blocked: true,
      ),
      WebCategory(
        id: 'drugs',
        name: 'Drugs & alcohol',
        description: 'Substance-related content',
        icon: Icons.medication_liquid_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      WebCategory(
        id: 'social',
        name: 'Social networks',
        description: 'Social media websites',
        icon: Icons.groups_rounded,
        color: const Color(0xFF3B82F6),
      ),
      WebCategory(
        id: 'weapons',
        name: 'Weapons',
        description: 'Firearms and weapon sales',
        icon: Icons.gpp_bad_rounded,
        color: const Color(0xFF64748B),
      ),
      WebCategory(
        id: 'malware',
        name: 'Malware',
        description: 'Malicious and infected sites',
        icon: Icons.bug_report_rounded,
        color: const Color(0xFFB91C1C),
        blocked: true,
      ),
      WebCategory(
        id: 'phishing',
        name: 'Phishing & scams',
        description: 'Fake login and scam sites',
        icon: Icons.phishing_rounded,
        color: const Color(0xFF0EA5E9),
        blocked: true,
      ),
    ];
