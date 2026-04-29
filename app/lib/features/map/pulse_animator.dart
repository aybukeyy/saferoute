// Pulse animation for a freshly-classified cell.
//
// Drives a single cell's color from grey -> orange -> red -> hold -> fade
// over ~2 seconds total. Triggered by the SyncService.watchCells stream when
// a remote pulse event arrives. See PLAN.md §4.1 — this is the "live
// heatmap pulse" demo beat.
//
// Visual contract (must hold for the video):
//   t = 0      -> 600 ms    : grey -> orange (Color.lerp)
//   t = 600    -> 1200 ms   : orange -> red
//   t = 1200   -> 2000 ms   : red sustained, alpha fades 220 -> 0
// Total: 2.0 s exactly. onCompleted fires on dismiss.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/geohash.dart';

/// Total pulse duration. Tuned for the demo beat — do NOT change without
/// re-shooting Scene 5.
const Duration kPulseDuration = Duration(milliseconds: 2000);

/// One pulse instance. Wrapped by [PulseLayer] which owns the actual map
/// projection.
class PulseAnimator extends StatefulWidget {
  const PulseAnimator({
    super.key,
    required this.geohash7,
    required this.onCompleted,
    this.duration = kPulseDuration,
  });

  final String geohash7;
  final VoidCallback onCompleted;
  final Duration duration;

  @override
  State<PulseAnimator> createState() => PulseAnimatorState();
}

class PulseAnimatorState extends State<PulseAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onCompleted();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Color & alpha for a given normalized progress `t` in `[0, 1]`. Pulled
  /// out so unit tests can assert the colour curve without a Ticker.
  static (Color color, int alpha) sampleAt(double t) {
    if (t < 0.3) {
      // 0 -> 600ms : grey -> orange
      final local = (t / 0.3).clamp(0.0, 1.0);
      return (Color.lerp(Colors.grey, kRiskMid, local)!, 200);
    } else if (t < 0.6) {
      // 600 -> 1200ms : orange -> red
      final local = ((t - 0.3) / 0.3).clamp(0.0, 1.0);
      return (Color.lerp(kRiskMid, kRiskHigh, local)!, 220);
    } else {
      // 1200 -> 2000ms : red sustain, alpha fades 220 -> 0
      final local = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
      final alpha = (220 * (1 - local)).round().clamp(0, 255);
      return (kRiskHigh, alpha);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final bounds = Geohash.bounds(widget.geohash7);
    final swPx = camera.latLngToScreenOffset(LatLng(bounds.minLat, bounds.minLng));
    final nePx = camera.latLngToScreenOffset(LatLng(bounds.maxLat, bounds.maxLng));
    final rect = Rect.fromLTRB(swPx.dx, nePx.dy, nePx.dx, swPx.dy);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final (color, alpha) = sampleAt(_controller.value);
        return CustomPaint(
          painter: _PulseRectPainter(
            rect: rect,
            color: color.withValues(alpha: alpha / 255),
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _PulseRectPainter extends CustomPainter {
  _PulseRectPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawRect(rect, p);
    final stroke = Paint()
      ..color = color.withValues(alpha: 1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(covariant _PulseRectPainter old) =>
      old.color != color || old.rect != rect;
}

/// flutter_map layer that hosts a stack of in-flight pulses. The MapScreen
/// pushes a new geohash via [PulseLayerController] when a SyncService event
/// arrives; the layer disposes finished pulses automatically.
class PulseLayer extends StatefulWidget {
  const PulseLayer({super.key, required this.controller});

  final PulseLayerController controller;

  @override
  State<PulseLayer> createState() => _PulseLayerState();
}

class _PulseLayerState extends State<PulseLayer> {
  late VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () => setState(() {});
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.activePulses;
    if (active.isEmpty) return const SizedBox.shrink();

    return MobileLayerTransformer(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final entry in active)
              PulseAnimator(
                key: ValueKey(entry.id),
                geohash7: entry.geohash7,
                onCompleted: () => widget.controller._remove(entry.id),
              ),
          ],
        ),
      ),
    );
  }
}

class PulseEntry {
  PulseEntry(this.id, this.geohash7);
  final int id;
  final String geohash7;
}

class PulseLayerController extends ChangeNotifier {
  final List<PulseEntry> _active = <PulseEntry>[];
  int _seq = 0;

  Iterable<PulseEntry> get activePulses => List.unmodifiable(_active);

  void pulseCell(String geohash7) {
    _active.add(PulseEntry(_seq++, geohash7));
    notifyListeners();
  }

  void _remove(int id) {
    _active.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
