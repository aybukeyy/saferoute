import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:latlong2/latlong.dart';

part 'route_result.freezed.dart';

/// Result of `RoutingService.findRoutes`. The two polylines are the headline
/// visual; `explanationCard` powers the three-layer explainable-AI sheet.
/// See ARCHITECTURE.md §6 and §7.
///
/// Note: deliberately not JSON-serializable. `LatLng` (latlong2) does not
/// expose a from/to-JSON contract and these results are computed on-device,
/// not synced.
@freezed
abstract class RouteResult with _$RouteResult {
  const factory RouteResult({
    required List<LatLng> shortestPath,
    required List<LatLng> safestPath,
    required List<String> avoidedCells,
    required RouteExplanation explanationCard,
  }) = _RouteResult;
}

/// Structured payload behind the Layer-1 (route-level) explanation chips.
/// `gemmaSummary` is the optional Gemma 4 E4B one-sentence brief; null until
/// the cached summary is available.
@freezed
abstract class RouteExplanation with _$RouteExplanation {
  const factory RouteExplanation({
    required Map<String, String> avoidedCellSummaries,
    required double nightMultiplier,
    required double surgeMultiplier,
    required double distanceDeltaMeters,
    required int timeDeltaSeconds,
    String? gemmaSummary,
  }) = _RouteExplanation;
}
