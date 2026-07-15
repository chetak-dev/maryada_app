import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/geofence_repository.dart';
import '../../data/location_repository.dart';
import '../../models/child.dart';
import '../../models/geofence.dart';
import '../../theme/tokens.dart';

/// Location & places: a live-location card (stylised map placeholder for now),
/// and the child's geofenced places. Places persist to Firestore when live.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, this.childName, this.familyId, this.childId});

  final String? childName;
  final String? familyId;
  final String? childId;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _geofences = demoGeofences();

  bool get _live => widget.familyId != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'Location'
        : 'Location · ${widget.childName}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
        children: [
          if (_live)
            StreamBuilder<List<Child>>(
              stream: FamilyRepository.instance.watchChildren(widget.familyId!),
              builder: (context, snap) {
                final kids = snap.data ?? const <Child>[];

                // Per-child view: that child's location + history.
                if (widget.childId != null) {
                  Child? c;
                  for (final k in kids) {
                    if (k.id == widget.childId) {
                      c = k;
                      break;
                    }
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LiveLocationCard(child: c),
                      if (c != null && c.hasLocation) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text('Location history',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        _HistoryList(familyId: widget.familyId!, childId: c.id),
                      ],
                    ],
                  );
                }

                // Common view: every child's location, no history.
                final located = kids.where((k) => k.hasLocation).toList();
                if (located.isEmpty) return const _LiveLocationCard();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in located) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(c.name,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      _LiveLocationCard(child: c),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              },
            )
          else
            const _LiveLocationCard(),
          const SizedBox(height: AppSpacing.lg),
          Text('Places', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_live)
            StreamBuilder<List<Geofence>>(
              stream: GeofenceRepository.instance.watch(widget.familyId!),
              builder: (context, snap) {
                final places = snap.data ?? const <Geofence>[];
                if (places.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('No places yet.',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: places
                      .map((g) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _GeofenceCard(geofence: g),
                          ))
                      .toList(),
                );
              },
            )
          else
            ..._geofences.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _GeofenceCard(geofence: g),
                )),
        ],
      ),
    );
  }
}

class _LiveLocationCard extends StatelessWidget {
  const _LiveLocationCard({this.child});
  final Child? child;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = child;
    final hasLoc = c != null && c.hasLocation;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: hasLoc
                ? _MapThumb(lat: c.lat!, lng: c.lng!)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primary.withValues(alpha: 0.18),
                              AppColors.accent.withValues(alpha: 0.14),
                            ],
                          ),
                        ),
                      ),
                      CustomPaint(painter: _GridPainter(), size: Size.infinite),
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_searching_rounded,
                                color: AppColors.primary, size: 44),
                            SizedBox(height: 4),
                            Text('Waiting for device location…',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasLoc
                            ? (c.address != null && c.address!.isNotEmpty
                                ? c.address!
                                : '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}')
                            : 'No location yet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        hasLoc && c.locationUpdatedAt != null
                            ? 'Updated ${_ago(c.locationUpdatedAt!)}'
                            : 'The device will report its location once online',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (hasLoc && c.locationAccuracy != null)
                  Row(
                    children: [
                      const Icon(Icons.gps_fixed_rounded,
                          color: AppColors.accent, size: 18),
                      const SizedBox(width: 4),
                      Text('±${c.locationAccuracy!.round()}m',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight map thumbnail built from a single OpenStreetMap tile centred
/// on the reported position (no map SDK / API key needed).
class _MapThumb extends StatelessWidget {
  const _MapThumb({required this.lat, required this.lng});
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    const z = 16;
    final n = 1 << z;
    final latRad = lat * math.pi / 180.0;
    final xF = (lng + 180.0) / 360.0 * n;
    final yF = (1 -
            math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        n;
    final xt = xF.floor();
    final yt = yF.floor();
    final url = 'https://tile.openstreetmap.org/$z/$xt/$yt.png';
    final ax = (xF - xt) * 2 - 1;
    final ay = (yF - yt) * 2 - 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.accent.withValues(alpha: 0.14),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment(ax.clamp(-1.0, 1.0), ay.clamp(-1.0, 1.0)),
          child: const Icon(Icons.location_on_rounded,
              color: AppColors.primary, size: 40),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GeofenceCard extends StatelessWidget {
  const _GeofenceCard({required this.geofence});
  final Geofence geofence;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: geofence.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(geofence.icon, color: geofence.color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(geofence.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${geofence.address} · ${geofence.radiusMeters}m',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.familyId, required this.childId});
  final String familyId;
  final String childId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocationPoint>>(
      stream: LocationRepository.instance.watchHistory(familyId, childId),
      builder: (context, snap) {
        final points = snap.data ?? const <LocationPoint>[];
        if (points.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('No history yet.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (var i = 0; i < points.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _HistoryTile(point: points[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.point});
  final LocationPoint point;

  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) return 'Today $time';
    return '${t.day}/${t.month} $time';
  }

  @override
  Widget build(BuildContext context) {
    final title = (point.address != null && point.address!.isNotEmpty)
        ? point.address!
        : '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.location_on_rounded,
            color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(_when(point.at)),
    );
  }
}
