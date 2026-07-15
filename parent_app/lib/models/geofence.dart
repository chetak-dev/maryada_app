import 'package:flutter/material.dart';

/// A named place with a radius that raises alerts on enter/exit (UI model).
class Geofence {
  final String id;
  final String name;
  final String address;
  final int radiusMeters;
  final IconData icon;
  final Color color;
  bool notifyOnArrive;
  bool notifyOnLeave;

  Geofence({
    required this.id,
    required this.name,
    required this.address,
    required this.radiusMeters,
    required this.icon,
    required this.color,
    this.notifyOnArrive = true,
    this.notifyOnLeave = true,
  });

  factory Geofence.fromMap(String id, Map<String, dynamic> map) => Geofence(
        id: id,
        name: (map['name'] ?? 'Place').toString(),
        address: (map['address'] ?? '').toString(),
        radiusMeters: (map['radiusMeters'] as num?)?.toInt() ?? 150,
        icon: Icons.place_rounded,
        color: const Color(0xFF4F46E5),
        notifyOnArrive: map['notifyOnArrive'] != false,
        notifyOnLeave: map['notifyOnLeave'] != false,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'radiusMeters': radiusMeters,
        'notifyOnArrive': notifyOnArrive,
        'notifyOnLeave': notifyOnLeave,
      };
}

List<Geofence> demoGeofences() => [
      Geofence(
        id: 'home',
        name: 'Home',
        address: '221B Baker Street',
        radiusMeters: 150,
        icon: Icons.home_rounded,
        color: const Color(0xFF10B981),
      ),
      Geofence(
        id: 'school',
        name: 'School',
        address: 'Greenfield High',
        radiusMeters: 200,
        icon: Icons.school_rounded,
        color: const Color(0xFF3B82F6),
      ),
    ];
