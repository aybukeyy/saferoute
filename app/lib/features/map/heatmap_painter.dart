// CustomPainter that draws the per-cell risk heatmap as an overlay on top
// of the OSM tiles. One filled rectangle per geohash-7 cell, gradient
// coloured by score. See PLAN.md §4.1 (Visual Wow) and ARCHITECTURE.md §6.
//
// Performance notes
//  - shouldRepaint compares the camera fingerprint (zoom + center +
//    rotation) and the data identity. A pan that doesn't change zoom only
//    re-paints when the bbox-derived heatmap snapshot changes, not every
//    frame.
//  - The painter takes pre-computed cell bounds (lat/lng degrees), not
//    geohashes, so we only run the geohash → bounds decode in the data
//    layer, not in paint().

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';

/// One cell's geometry + score, ready to paint.
class HeatmapCell {
  const HeatmapCell({
    required this.geohash7,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.score,
  });

  final String geohash7;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  /// Normalized predicted_risk in `[0, 1]`.
  final double score;
}

/// Paints the heatmap cells on top of the map. Used inside a
/// `MobileLayerTransformer`-aware `CustomPaint` (see HeatmapLayer below).
class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.cells,
    required this.camera,
  });

  final List<HeatmapCell> cells;
  final MapCamera camera;

  /// Maps the cumulative additive intensity at a pixel to a "demand heatmap"
  /// colour ramp (transparent → cool yellow → warm orange → hot red). Returned
  /// only by [colorForScore] for tests that still want a per-cell colour.
  static Color colorForScore(double score) {
    if (score <= 0) return kRiskLow.withValues(alpha: 0);
    if (score < 0.33) {
      return Color.lerp(kRiskLow, kRiskMid, score / 0.33)!
          .withValues(alpha: 180 / 255);
    }
    if (score < 0.66) {
      return Color.lerp(kRiskMid, kRiskHigh, (score - 0.33) / 0.33)!
          .withValues(alpha: 220 / 255);
    }
    return kRiskHigh.withValues(alpha: 240 / 255);
  }

  /// Demand-style heatmap: each cell paints a soft radial gradient blob,
  /// blobs accumulate via [BlendMode.plus] so overlapping cells brighten and
  /// dense regions naturally bloom into a hot core. No hex outlines, no
  /// per-cell borders — the texture comes from the additive overlap.
  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty) return;
    final visible = camera.visibleBounds;

    // Render the heatmap into an offscreen layer so [BlendMode.plus] only
    // mixes the blobs with each other, not with the underlying tiles.
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final cell in cells) {
      if (cell.maxLat < visible.south ||
          cell.minLat > visible.north ||
          cell.maxLng < visible.west ||
          cell.minLng > visible.east) {
        continue;
      }

      final swPx = camera.latLngToScreenOffset(
          LatLng(cell.minLat, cell.minLng));
      final nePx = camera.latLngToScreenOffset(
          LatLng(cell.maxLat, cell.maxLng));
      final cx = (swPx.dx + nePx.dx) / 2;
      final cy = (swPx.dy + nePx.dy) / 2;
      final halfW = (nePx.dx - swPx.dx).abs() / 2;
      final halfH = (swPx.dy - nePx.dy).abs() / 2;
      // Generous radius so neighbouring blobs overlap heavily — that overlap
      // is what produces the "denser = redder" bloom.
      final cellSize = math.max(halfW, halfH);
      final radius = cellSize * 2.4;

      // Per-blob intensity scales with score. Low scores stay dim so cool
      // areas don't pollute the additive sum.
      final intensity = cell.score.clamp(0.0, 1.0).toDouble();
      // Squeeze toward the warm end of the ramp for high-density cells.
      final hot = Color.lerp(kRiskMid, kRiskHigh, intensity)!;

      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          radius,
          [
            hot.withValues(alpha: (0.55 * intensity).clamp(0.05, 0.6)),
            hot.withValues(alpha: 0),
          ],
          const [0.0, 1.0],
        );
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HeatmapPainter oldDelegate) {
    // Identity check on the cells list — providers hand us a new list only
    // when the snapshot changes, so reference equality is correct here.
    if (!identical(oldDelegate.cells, cells)) return true;
    return oldDelegate.camera.zoom != camera.zoom ||
        oldDelegate.camera.center.latitude != camera.center.latitude ||
        oldDelegate.camera.center.longitude != camera.center.longitude ||
        oldDelegate.camera.rotation != camera.rotation;
  }
}

/// flutter_map layer wrapper. Drop into `FlutterMap.children` after the
/// tile layer.
class HeatmapLayer extends StatelessWidget {
  const HeatmapLayer({super.key, required this.cells});

  final List<HeatmapCell> cells;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(
          painter: HeatmapPainter(cells: cells, camera: camera),
          size: Size.infinite,
        ),
      ),
    );
  }
}
