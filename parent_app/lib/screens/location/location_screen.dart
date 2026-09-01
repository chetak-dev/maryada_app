import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../data/geofence_repository.dart';
import '../../data/location_repository.dart';
import '../../models/child.dart';
import '../../models/geofence.dart';
import '../../theme/tokens.dart';

/// Location & places: a live map per child, and the child's geofenced places.
/// Places persist to Firestore when live.
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

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = child;
    final hasLoc = c != null && c.hasLocation;
    if (!hasLoc) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 260,
          child: Stack(
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
      );
    }

    // The map fills the card and the details float over it — the map is the
    // content here, not a thumbnail above a text row.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 400,
        child: Stack(
          children: [
            Positioned.fill(
              child: _MapThumb(
                lat: c.lat!,
                lng: c.lng!,
                accuracy: c.locationAccuracy,
                markerColor: c.avatarColor,
                markerInitials: c.initials,
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadow.card,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: c.avatarColor,
                      child: Text(
                        c.initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.address != null && c.address!.isNotEmpty
                                ? c.address!
                                : '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                height: 1.25),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (c.locationUpdatedAt != null)
                                'Updated ${_ago(c.locationUpdatedAt!)}',
                              if (c.locationAccuracy != null)
                                'accurate to ${c.locationAccuracy!.round()} m',
                            ].join(' · '),
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(
                      tooltip: 'Open in Maps',
                      onPressed: () => _openInMaps(c.lat!, c.lng!),
                      icon: const Icon(Icons.directions_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An interactive map centred on the reported position. Replaces a single
/// 256px OpenStreetMap tile stretched to fill the card, which was blurry and
/// couldn't be panned or zoomed.
class _MapThumb extends StatefulWidget {
  const _MapThumb({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.markerColor = AppColors.primary,
    this.markerInitials = '',
  });

  final double lat;
  final double lng;
  final double? accuracy;
  final Color markerColor;
  final String markerInitials;

  @override
  State<_MapThumb> createState() => _MapThumbState();
}

class _MapThumbState extends State<_MapThumb> {
  final _controller = MapController();

  @override
  void didUpdateWidget(_MapThumb old) {
    super.didUpdateWidget(old);
    // A fresh report moves the pin; follow it.
    if (old.lat != widget.lat || old.lng != widget.lng) {
      _controller.move(LatLng(widget.lat, widget.lng), _controller.camera.zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Inverts the light basemap, then rotates hue 180° so parks stay green and
  /// water stays blue instead of going magenta.
  static const _darkBasemapFilter = ColorFilter.matrix(<double>[
    0.574, -1.430, -0.144, 0, 255, //
    -0.426, -0.430, -0.144, 0, 255, //
    -0.426, -1.430, 0.856, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  Widget _basemap(BuildContext context, bool isDark) {
    final tiles = TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      // Esri serves a "Map data not yet available" placeholder past z17 over
      // much of India. Retina simulation requests one zoom deeper than shown,
      // and flutter_map caps that request at exactly maxNativeZoom — so 17
      // keeps tiles sharp while never asking for the placeholder band.
      maxNativeZoom: 17,
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: 'com.guardnest.guardnest_parent',
    );
    // Esri has no dark basemap that keeps street detail at this zoom, so the
    // dark map is derived from the light one.
    return isDark
        ? ColorFiltered(colorFilter: _darkBasemapFilter, child: tiles)
        : tiles;
  }

  @override
  Widget build(BuildContext context) {
    final here = LatLng(widget.lat, widget.lng);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: here,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            _basemap(context, isDark),
            if (widget.accuracy != null && widget.accuracy! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: here,
                    radius: widget.accuracy!,
                    useRadiusInMeter: true,
                    color: widget.markerColor.withValues(alpha: 0.15),
                    borderColor: widget.markerColor.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // An avatar pin (initials in the child's colour) rather than an
                // anonymous dot, so the map reads as "this is where Aarav is".
                Marker(
                  point: here,
                  width: 44,
                  height: 54,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          widget.markerInitials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      // The pin tip anchoring the avatar to the exact spot.
                      CustomPaint(
                        size: const Size(12, 8),
                        painter: _PinTipPainter(widget.markerColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution('Esri, HERE, Garmin'),
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: Material(
            color: AppColors.surfaceOf(context),
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: 'Recenter',
              onPressed: () => _controller.move(here, 16),
              icon: const Icon(Icons.my_location_rounded,
                  size: 20, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinTipPainter extends CustomPainter {
  _PinTipPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // latlong2 exports its own Path type, so the dart:ui one needs the prefix.
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTipPainter oldDelegate) =>
      oldDelegate.color != color;
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

  /// Bucket labels in display order; a point falls in the first that matches.
  static String _bucketOf(DateTime? t) {
    if (t == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final days = today.difference(that).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'This week';
    if (days < 31) return 'This month';
    return 'Earlier';
  }

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

        // Points arrive newest-first, so buckets appear in order as the label
        // changes while walking the list.
        final sections = <Widget>[];
        String? bucket;
        var group = <LocationPoint>[];
        void flush() {
          final label = bucket;
          if (label == null || group.isEmpty) return;
          sections
            ..add(_HistorySectionHeader(label: label, count: group.length))
            ..add(Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                children: [
                  for (var i = 0; i < group.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _HistoryTile(point: group[i]),
                  ],
                ],
              ),
            ));
          group = <LocationPoint>[];
        }

        for (final p in points) {
          final b = _bucketOf(p.at);
          if (b != bucket) {
            flush();
            bucket = b;
          }
          group.add(p);
        }
        flush();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: sections,
        );
      },
    );
  }
}

class _HistorySectionHeader extends StatelessWidget {
  const _HistorySectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Container(height: 1, color: AppColors.borderOf(context))),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.point});
  final LocationPoint point;

  /// Section headers carry the day, so the tile only needs the clock time —
  /// plus the date for entries older than yesterday.
  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    if (today.difference(that).inDays <= 1) return time;
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
