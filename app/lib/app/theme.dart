import 'package:flutter/material.dart';

/// Design tokens for Safe Route. Colors are referenced by the heatmap
/// painter, the route polyline renderer, and the explanation chips. Keep
/// them centralized so a single edit re-skins the whole demo before video
/// shoot day.

/// Risk gradient — used by the heatmap painter and the avoided-cell
/// outlines. Low/mid/high map directly to `RiskLevel` enum buckets.
const Color kRiskLow = Color(0xFFFFC857); // amber 300 — low/baseline
const Color kRiskMid = Color(0xFFFF8C42); // orange 600 — moderate
const Color kRiskHigh = Color(0xFFE5383B); // red 600 — high / pulse target

/// Route polylines. The "shortest" baseline draws first in muted grey,
/// the "safest" sweeps in over ~600ms in emerald — see ARCHITECTURE.md §6.
const Color kRouteShortest = Color(0xFF6C757D); // slate 500
const Color kRouteSafest = Color(0xFF2A9D8F); // emerald / teal — brand seed

/// Build the app-wide Material 3 light theme. Dark mode is intentionally
/// out of scope for the hackathon demo (video is shot in daylight + indoor
/// lighting; dark mode would slow down the heatmap colour calibration).
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kRouteSafest,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
