import 'package:flutter/material.dart';

/// A label a guardian can put on a profile to group it — "Class 8", "Hostel".
///
/// Tags belong to one family, so two households can both have a "Class 8"
/// without colliding. The site admin owns the vocabulary; a guardian with edit
/// access decides which of their children wear which tag.
class FamilyTag {
  final String id;
  final String name;
  final Color color;

  const FamilyTag({
    required this.id,
    required this.name,
    required this.color,
  });

  factory FamilyTag.fromMap(String id, Map<String, dynamic> m) => FamilyTag(
    id: id,
    name: (m['name'] ?? '').toString(),
    color: Color(m['color'] is int ? m['color'] as int : tagPalette.first),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    // ignore: deprecated_member_use — `value` is the stored form; toARGB32()
    // is not available on the SDK this project targets.
    'color': color.toARGB32(),
  };
}

/// Colours offered when creating a tag. Deliberately few and muted: a tag is a
/// grouping, and must never shout louder than a profile's protection status.
const tagPalette = <int>[
  0xFF4F46E5, // indigo
  0xFF0EA5E9, // sky
  0xFF10B981, // emerald
  0xFFF59E0B, // amber
  0xFFEC4899, // pink
  0xFF8B5CF6, // violet
  0xFF64748B, // slate
];
