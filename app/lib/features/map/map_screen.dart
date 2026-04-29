// Main app screen — full-bleed flutter_map with the OSM tile layer, the
// custom risk-heatmap overlay, the live pulse layer, and the two FABs that
// lead to the report sheet and the route planner.
//
// Provider wiring is via lib/features/providers.dart. The Integration
// agent overrides those providers with the real data/sync/routing services
// in main.dart.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geohash.dart';
import '../providers.dart';
import '../report/report_sheet.dart';
import 'heatmap_painter.dart';
import 'pulse_animator.dart';

/// Default map center used until GPS resolves. Beşiktaş, Istanbul — matches
/// the bundled demo seed (`assets/seed_reports.json`) and the recommended
/// `tools/extract_osm.py --bbox` for IMPLEMENTATION.md §7.
const LatLng kDefaultMapCenter = LatLng(41.060, 29.015);
const double kDefaultZoom = 14;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  final _pulseController = PulseLayerController();

  // Latest visible bbox; recomputed when the map idles. Used as the family
  // key for heatmap + pulse providers.
  BoundingBox? _bbox;

  // Tracks which sync subscription bbox we already wired so we don't
  // subscribe twice on rebuild.
  BoundingBox? _wiredBbox;

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
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
    final initialCenter = positionAsync.maybeWhen(
      data: (p) => p,
      orElse: () => kDefaultMapCenter,
    );

    // Wire the pulse stream once we know the bbox.
    if (_bbox != null && _bbox != _wiredBbox) {
      _wiredBbox = _bbox;
      ref.listen(cellPulseStreamProvider(_bbox!), (prev, next) {
        next.whenData((pulse) => _pulseController.pulseCell(pulse.geohash7));
      });
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Safe Route'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'about') context.push('/about');
              if (v == 'feed') context.push('/feed');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'feed', child: Text('Recent reports')),
              PopupMenuItem(value: 'about', child: Text('About')),
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
              if (_bbox != null) _HeatmapBinder(bbox: _bbox!),
              PulseLayer(controller: _pulseController),
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
          // Bottom-left "route" FAB.
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'fab-route',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              tooltip: 'Plan a route',
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
              label: const Text('Report'),
              icon: const Icon(Icons.add_alert),
              onPressed: () => showReportSheet(context),
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
