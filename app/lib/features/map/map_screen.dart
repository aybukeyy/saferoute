// Main app screen — full-bleed flutter_map with the OSM tile layer, the
// custom risk-heatmap overlay, the live pulse layer, and the two FABs that
// lead to the report sheet and the route planner.
//
// Provider wiring is via lib/features/providers.dart. The Integration
// agent overrides those providers with the real data/sync/routing services
// in main.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geohash.dart';
import '../../core/l10n/app_strings.dart';
import '../emergency/emergency_fab.dart';
import '../emergency/emergency_providers.dart';
import '../emergency/emergency_settings_screen.dart';
import '../providers.dart';
import '../report/report_sheet.dart';
import 'heatmap_painter.dart';

/// How often the heatmap polls SQLite for fresh risk-cell data. Newly
/// submitted reports (especially emergencies) update `risk_cells` directly
/// but don't push back to the provider, so the cached snapshot stays stale
/// otherwise. 2 s is fast enough that the user sees their submission
/// darken within a beat.
const Duration _kHeatmapRefreshInterval = Duration(seconds: 2);

/// Default map center used until GPS resolves. Beşiktaş, Istanbul — matches
/// the bundled demo seed (`assets/seed_reports.json`) and the recommended
/// `tools/extract_osm.py --bbox` for IMPLEMENTATION.md §7.
const LatLng kDefaultMapCenter = LatLng(41.060, 29.015);
const double kDefaultZoom = 14;

/// Fixed bbox the heatmap renders for. Independent of camera pan/zoom so the
/// red blobs stay anchored to real-world locations and don't visually shift
/// when the user moves the camera. Matches the bbox the seed JSON ships with.
const BoundingBox kDemoHeatmapBbox = BoundingBox(
  south: 41.040,
  west: 28.985,
  north: 41.080,
  east: 29.045,
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();

  // Latest visible bbox; recomputed when the map idles. Used as the family
  // key for the heatmap provider.
  BoundingBox? _bbox;

  Timer? _heatmapPoll;

  @override
  void initState() {
    super.initState();
    // Periodically nudge the heatmap so freshly-submitted reports (which
    // update risk_cells in SQLite but don't notify the provider) become
    // visible without a manual map gesture.
    _heatmapPoll = Timer.periodic(_kHeatmapRefreshInterval, (_) {
      if (!mounted) return;
      ref.read(heatmapRefreshTickProvider.notifier).bump();
    });
  }

  @override
  void dispose() {
    _heatmapPoll?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    // Update the bbox when the camera idles after a gesture or program move.
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      _refreshBbox();
    }
  }

  void _refreshBbox() {
    final cam = _mapController.camera;
    final v = cam.visibleBounds;
    final next = BoundingBox(
      south: v.south,
      west: v.west,
      north: v.north,
      east: v.east,
    );
    if (_bbox != next) {
      setState(() => _bbox = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(currentLocationProvider);
    final strings = ref.watch(stringsProvider);
    final initialCenter = positionAsync.maybeWhen(
      data: (p) => p,
      orElse: () => kDefaultMapCenter,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(strings.appTitle),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text(
                'Test',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => context.push('/demo'),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'about') context.push('/about');
              if (v == 'feed') context.push('/feed');
              if (v == 'settings') context.push('/settings');
              if (v == 'emergency_contact') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmergencySettingsScreen(),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'feed', child: Text(strings.menuRecentReports)),
              PopupMenuItem(
                value: 'emergency_contact',
                child: Text(strings.menuEmergencyContact),
              ),
              PopupMenuItem(value: 'settings', child: Text(strings.menuSettings)),
              PopupMenuItem(value: 'about', child: Text(strings.menuAbout)),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: kDefaultZoom,
              minZoom: 11,
              maxZoom: 19,
              onMapEvent: _onMapEvent,
              onMapReady: _refreshBbox,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.evam.saferoute',
                maxZoom: 19,
              ),
              const _HeatmapBinder(bbox: kDemoHeatmapBbox),
              if (positionAsync.hasValue)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 22,
                      height: 22,
                      point: positionAsync.value!,
                      child: const _SelfMarker(),
                    ),
                  ],
                ),
            ],
          ),
          // Top-left "center on me" FAB.
          Positioned(
            left: 16,
            top: 16,
            child: FloatingActionButton.small(
              heroTag: 'fab-locate',
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.primary,
              tooltip: strings.locateTooltip,
              onPressed: () {
                final pos = ref.read(currentLocationProvider).maybeWhen(
                      data: (p) => p,
                      orElse: () => null,
                    );
                if (pos == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(strings.locationNotReady),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                _mapController.move(pos, 16);
                _refreshBbox();
              },
              child: const Icon(Icons.my_location),
            ),
          ),
          // Bottom-left "route" FAB.
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'fab-route',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              tooltip: strings.planRouteTooltip,
              onPressed: () => context.push('/route'),
              child: const Icon(Icons.alt_route),
            ),
          ),
          // Bottom-right report FAB.
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab-report',
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              label: Text(strings.reportFabLabel),
              icon: const Icon(Icons.add_alert),
              onPressed: () => showReportSheet(context),
            ),
          ),
          // Emergency FAB above the report FAB.
          Positioned(
            right: 16,
            bottom: 88,
            child: EmergencyFab(
              actionBuilder: ref.read(emergencyActionBuilderProvider),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the heatmap snapshot and projects each cell's bounds, then hands
/// the ready-to-paint list to [HeatmapLayer]. Lives inside the FlutterMap
/// child tree so MapCamera.of(context) returns the live camera.
class _HeatmapBinder extends ConsumerWidget {
  const _HeatmapBinder({required this.bbox});

  final BoundingBox bbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(heatmapDataProvider(bbox));
    final cells = <HeatmapCell>[];
    data.forEach((gh, score) {
      final b = Geohash.bounds(gh);
      cells.add(HeatmapCell(
        geohash7: gh,
        minLat: b.minLat,
        maxLat: b.maxLat,
        minLng: b.minLng,
        maxLng: b.maxLng,
        score: score,
      ));
    });
    debugPrint('[heatmap] data=${data.length} cells=${cells.length} bbox=$bbox'
        '${cells.isNotEmpty ? " first=(${cells.first.geohash7}, ${cells.first.score.toStringAsFixed(2)})" : ""}');
    return HeatmapLayer(cells: cells);
  }
}

class _SelfMarker extends StatelessWidget {
  const _SelfMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
    );
  }
}
