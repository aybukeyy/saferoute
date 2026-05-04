// RouteDetailScreen — the demo's headline visual (DEMO.md Scene 6).
//
// - Map full-screen with the OSM tile layer.
// - Shortest route polyline draws instantly in muted slate.
// - Safest route polyline animates in over ~600 ms (length-progressive
//   reveal driven by an AnimationController + custom path painter).
// - Avoided cells get a 1.5 px red outline + a floating reason label that
//   fades in sequentially as the safe polyline reaches each cell.
// - Bottom peek sheet exposes "+180 m, +2 min" trade-off and the "Why is
//   this safer?" CTA → ExplanationCard.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/geohash.dart';
import '../../models/route_result.dart';
import '../explanation/explanation_card.dart';
import '../map/heatmap_painter.dart';
import '../map/map_screen.dart' show kDemoHeatmapBbox;
import '../providers.dart';
import 'route_planner_screen.dart';
import 'route_share_control.dart';
import 'tts_navigator.dart';

/// Length of the safe-route reveal sweep. Tuned for the video — keep at
/// 600 ms unless re-shooting Scene 6.
const Duration kSafeRouteSweepDuration = Duration(milliseconds: 600);

class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.request});

  final RouteRequest request;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  bool _muted = false;

  void _toggleMute() {
    setState(() => _muted = !_muted);
  }

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(routeResultProvider(RouteQuery(
      from: widget.request.from,
      to: widget.request.to,
      time: widget.request.time,
    )));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route'),
        actions: [
          IconButton(
            tooltip: _muted ? 'Unmute voice' : 'Mute voice',
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            onPressed: _toggleMute,
          ),
          routeAsync.maybeWhen(
            data: (result) => RouteShareControl(
              request: widget.request,
              result: result,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: routeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Routing failed: $e')),
        data: (result) => _RouteContent(
          request: widget.request,
          result: result,
          muted: _muted,
        ),
      ),
    );
  }
}

class _RouteContent extends ConsumerStatefulWidget {
  const _RouteContent({
    required this.request,
    required this.result,
    required this.muted,
  });

  final RouteRequest request;
  final RouteResult result;
  final bool muted;

  @override
  ConsumerState<_RouteContent> createState() => _RouteContentState();
}

class _RouteContentState extends ConsumerState<_RouteContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  TtsNavigator? _navigator;
  ProviderSubscription<AsyncValue<LatLng>>? _locationSub;
  StreamController<LatLng>? _positionController;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: kSafeRouteSweepDuration)
      ..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapNavigator());
  }

  void _bootstrapNavigator() {
    if (!mounted) return;
    final lang = Localizations.maybeLocaleOf(context)?.languageCode == 'tr'
        ? 'tr'
        : 'en';
    final controller = StreamController<LatLng>.broadcast();
    _positionController = controller;
    final navigator = TtsNavigator(
      tts: FlutterTtsEngine(),
      polyline: widget.result.safestPath,
      avoidedCells: widget.result.avoidedCells,
      languageCode: lang,
    );
    _navigator = navigator;
    if (widget.muted) navigator.mute();
    navigator.start(controller.stream);
    _locationSub = ref.listenManual<AsyncValue<LatLng>>(
      currentLocationProvider,
      (prev, next) {
        next.whenData(controller.add);
      },
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(covariant _RouteContent old) {
    super.didUpdateWidget(old);
    if (widget.muted != old.muted) {
      if (widget.muted) {
        _navigator?.mute();
      } else {
        _navigator?.unmute();
      }
    }
  }

  @override
  void dispose() {
    _locationSub?.close();
    _navigator?.dispose();
    _positionController?.close();
    _sweep.dispose();
    super.dispose();
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    if (points.isEmpty) return LatLngBounds(const LatLng(0, 0), const LatLng(0, 0));
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _boundsFor([
      ...widget.result.shortestPath,
      ...widget.result.safestPath,
    ]);

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(56),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.evam.saferoute',
            ),
            // Risk heatmap underlay — same demand-style glow as MapScreen so
            // the user sees why the safe route detoured.
            const _RouteHeatmapBinder(),
            // Shortest route — instant.
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.result.shortestPath,
                  strokeWidth: 3,
                  color: kRouteShortest,
                ),
              ],
            ),
            // Safest route — animated reveal.
            AnimatedBuilder(
              animation: _sweep,
              builder: (_, _) {
                final revealed = _revealedPoints(
                    widget.result.safestPath, _sweep.value);
                return PolylineLayer(
                  polylines: [
                    Polyline(
                      points: revealed,
                      strokeWidth: 6,
                      color: kRouteSafest,
                    ),
                  ],
                );
              },
            ),
            // Avoided cells — circular danger badges over the heatmap glow.
            _AvoidedCellsOverlay(
              cells: widget.result.avoidedCells,
              progress: _sweep,
            ),
            // Endpoints.
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.request.from,
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
                ),
                Marker(
                  point: widget.request.to,
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.place, color: Colors.red, size: 32),
                ),
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _RoutePeekSheet(result: widget.result),
        ),
      ],
    );
  }

  /// Returns the prefix of [path] whose cumulative length is `progress` of
  /// the total length. Final segment is interpolated so the polyline grows
  /// smoothly rather than snapping vertex-by-vertex.
  static List<LatLng> _revealedPoints(List<LatLng> path, double progress) {
    if (path.length < 2 || progress <= 0) return const [];
    if (progress >= 1) return path;

    var totalLen = 0.0;
    final lens = <double>[];
    for (var i = 0; i + 1 < path.length; i++) {
      final l = _segLen(path[i], path[i + 1]);
      lens.add(l);
      totalLen += l;
    }
    if (totalLen == 0) return path;

    final target = totalLen * progress;
    var acc = 0.0;
    final out = <LatLng>[path.first];
    for (var i = 0; i + 1 < path.length; i++) {
      final segLen = lens[i];
      if (acc + segLen >= target) {
        final t = (target - acc) / segLen;
        final a = path[i];
        final b = path[i + 1];
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
        return out;
      }
      out.add(path[i + 1]);
      acc += segLen;
    }
    return out;
  }

  static double _segLen(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLng = a.longitude - b.longitude;
    return (dLat * dLat + dLng * dLng);
  }
}

class _AvoidedCellsOverlay extends StatelessWidget {
  const _AvoidedCellsOverlay({
    required this.cells,
    required this.progress,
  });

  final List<String> cells;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: progress,
      builder: (_, _) {
        final markers = <Marker>[];
        for (var i = 0; i < cells.length; i++) {
          final gh = cells[i];
          final b = Geohash.bounds(gh);
          final centerLat = (b.minLat + b.maxLat) / 2;
          final centerLng = (b.minLng + b.maxLng) / 2;

          // Sequential fade-in: cell i reveals as sweep crosses i/n.
          final threshold = (i + 1) / (cells.length + 1);
          final eased = (progress.value - threshold).clamp(0.0, 1.0);
          if (eased <= 0) continue;
          final opacity =
              (eased * 4).clamp(0.0, 1.0); // quick reveal, then hold

          // Big circular danger badge in place of the old red rectangle —
          // reads as "stay away" at a glance, plays well with the heatmap
          // glow underneath, and works on any zoom level. No text label —
          // the explanation card lists the reasons instead.
          markers.add(Marker(
            width: 56,
            height: 56,
            point: LatLng(centerLat, centerLng),
            child: Opacity(
              opacity: opacity,
              child: const _DangerBadge(),
            ),
          ));
        }
        return MarkerLayer(markers: markers);
      },
    );
  }
}

class _DangerBadge extends StatelessWidget {
  const _DangerBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kRiskHigh.withValues(alpha: 0.18),
      ),
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kRiskHigh,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: kRiskHigh.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Resolves the heatmap snapshot for the demo bbox and hands it to the
/// [HeatmapLayer] painter — same pattern as the MapScreen binder, scoped to
/// the route detail screen so the same red blobs show up on both surfaces.
class _RouteHeatmapBinder extends ConsumerWidget {
  const _RouteHeatmapBinder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(heatmapDataProvider(kDemoHeatmapBbox));
    if (data.isEmpty) return const SizedBox.shrink();
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
    return HeatmapLayer(cells: cells);
  }
}

class _RoutePeekSheet extends StatelessWidget {
  const _RoutePeekSheet({required this.result});

  final RouteResult result;

  @override
  Widget build(BuildContext context) {
    final exp = result.explanationCard;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: kRouteSafest),
              const SizedBox(width: 8),
              Text('Safest route', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '+${exp.distanceDeltaMeters.round()} m  ·  +${(exp.timeDeltaSeconds / 60).round()} min',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: FilledButton.tonalIcon(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => ExplanationCard(result: result),
                );
              },
              icon: const Icon(Icons.help_outline),
              label: const Text('Why is this safer?'),
            ),
          ),
        ],
      ),
    );
  }
}
