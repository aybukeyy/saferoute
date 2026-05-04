// Public viewer for a shared route. Subscribes to a `route_shares/{id}` doc
// and renders:
//   - The owner's safest-path polyline.
//   - A live marker that snaps to the latest [RouteShare.currentPosition].
//   - The owner's free-text message ("Eve dönüyorum, 25 dk").
//   - A "last updated" stamp + state badge (live / ended / expired).
//
// No auth required for the viewer — Firestore rules grant public read on
// active shares so anyone with the link sees the marker move.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/route_share_service.dart';
import '../../models/route_share.dart';

class RouteShareViewScreen extends ConsumerWidget {
  const RouteShareViewScreen({super.key, required this.shareId});

  final String shareId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svcAsync = ref.watch(routeShareServiceProvider);
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.shareViewerTitle)),
      body: svcAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(strings.shareViewerUnavailable('$e')),
          ),
        ),
        data: (svc) {
          if (!svc.isEnabled) {
            return _ViewerError(
              message: strings.shareViewerUnavailable(''),
            );
          }
          return StreamBuilder<RouteShare?>(
            stream: svc.watch(shareId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final share = snap.data;
              if (share == null) {
                return _ViewerError(
                  message: strings.shareViewerInvalid,
                );
              }
              return _ShareMap(share: share);
            },
          );
        },
      ),
    );
  }
}

class _ShareMap extends StatelessWidget {
  const _ShareMap({required this.share});

  final RouteShare share;

  @override
  Widget build(BuildContext context) {
    final bounds = _boundsFor([
      ...share.safestPath,
      share.currentPosition,
      share.from,
      share.to,
    ]);
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(48),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.evam.saferoute',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: share.safestPath,
                  strokeWidth: 5,
                  color: kRouteSafest,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: share.from,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.flag, color: Colors.blue, size: 26),
                ),
                Marker(
                  point: share.to,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.place, color: Colors.red, size: 30),
                ),
                Marker(
                  point: share.currentPosition,
                  width: 44,
                  height: 44,
                  child: _LiveDot(active: share.isActive),
                ),
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _ShareStatusSheet(share: share),
        ),
      ],
    );
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(const LatLng(0, 0), const LatLng(0, 0));
    }
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
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color =
        active ? Theme.of(context).colorScheme.primary : Colors.grey.shade600;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}

class _ShareStatusSheet extends ConsumerWidget {
  const _ShareStatusSheet({required this.share});

  final RouteShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(share: share),
              const Spacer(),
              Text(
                strings.shareEta(share.etaMinutes),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          if (share.message != null && share.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              share.message!,
              style: theme.textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            strings.shareLastUpdate(_formatRelative(share.updatedAt, strings)),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends ConsumerWidget {
  const _StatusBadge({required this.share});
  final RouteShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final (label, bg, fg) = _resolve(theme, strings);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color, Color) _resolve(ThemeData theme, AppStrings strings) {
    if (share.ended) {
      return (
        strings.shareArrived,
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      );
    }
    if (share.isExpired) {
      return (
        strings.shareExpired,
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.onSurface,
      );
    }
    return (
      strings.shareLive,
      theme.colorScheme.primaryContainer,
      theme.colorScheme.onPrimaryContainer,
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

String _formatRelative(DateTime t, AppStrings strings) {
  final diff = DateTime.now().toUtc().difference(t);
  if (diff.inSeconds < 30) return strings.relJustNow();
  if (diff.inMinutes < 1) return strings.relSeconds(diff.inSeconds);
  if (diff.inMinutes < 60) return strings.relMinutes(diff.inMinutes);
  if (diff.inHours < 24) return strings.relHours(diff.inHours);
  return strings.relDays(diff.inDays);
}
