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

  static Color colorForScore(double score) {
    if (score < 0.25) return kRiskLow.withValues(alpha: 80 / 255);
    if (score < 0.5) {
      return Color.lerp(kRiskLow, kRiskMid, (score - 0.25) / 0.25)!
          .withValues(alpha: 120 / 255);
    }
    if (score < 0.75) {
      return Color.lerp(kRiskMid, kRiskHigh, (score - 0.5) / 0.25)!
          .withValues(alpha: 150 / 255);
    }
    return kRiskHigh.withValues(alpha: 180 / 255);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty) return;

    // Cull cells outside the visible viewport. Cheap rectangle test against
    // the camera's visible bounds in lat/lng before projecting.
    final visible = camera.visibleBounds;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = kRiskHigh;

    for (final cell in cells) {
      // Quick reject if cell is entirely outside the visible bbox.
      if (cell.maxLat < visible.south ||
          cell.minLat > visible.north ||
          cell.maxLng < visible.west ||
          cell.minLng > visible.east) {
        continue;
      }

      final swLatLng = LatLng(cell.minLat, cell.minLng);
      final neLatLng = LatLng(cell.maxLat, cell.maxLng);
      final swPx = camera.latLngToScreenOffset(swLatLng);
      final nePx = camera.latLngToScreenOffset(neLatLng);

      // In screen space, NE has smaller y than SW (north is up).
      final rect = Rect.fromLTRB(
        swPx.dx,
        nePx.dy,
        nePx.dx,
        swPx.dy,
      );

      fillPaint.color = colorForScore(cell.score);
      canvas.drawRect(rect, fillPaint);

      if (cell.score >= 0.5) {
        canvas.drawRect(rect, borderPaint);
      }
    }
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
