// RoutePlannerScreen — pick a destination either by typing a place name
// (Nominatim typeahead in `place_search_field.dart`) or by tapping the map.
// Origin auto-fills from the current GPS. "Find route" pushes RouteDetail
// with the chosen pair.
//
// Search and tap stay in sync: picking a search result animates the map and
// drops a marker; tapping the map clears the search field so the displayed
// state always reflects the most recent input.
//
// Intentionally minimal — the visual wow lives in RouteDetail (animated
// polylines, avoided-cell labels). This screen is just the picker.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_screen.dart' show kDefaultMapCenter, kDefaultZoom;
import '../providers.dart';
import 'place_search.dart';
import 'place_search_field.dart';

/// Beşiktaş bias rectangle. Nominatim ranks results inside this box higher
/// without strictly excluding hits outside it — matches the demo's hot zone
/// without making the search useless if the user types "Kadıköy".
const PlaceSearchBias _kBesiktasBias = (
  minLng: 28.985,
  minLat: 41.040,
  maxLng: 29.045,
  maxLat: 41.080,
);

/// Zoom level the map snaps to when the user picks a search result. Tight
/// enough to make a single building visible; not so tight that we lose the
/// surrounding street grid.
const double _kFocusZoom = 16;

class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  ConsumerState<RoutePlannerScreen> createState() =>
      _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _destination;

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTap(TapPosition _, LatLng latlng) {
    // Tap-on-map wins — clear the search field so the UI reflects the
    // latest input method.
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    setState(() => _destination = latlng);
  }

  void _onPlaceSelected(PlaceSearchResult result) {
    final point = LatLng(result.lat, result.lng);
    setState(() => _destination = point);
    // `move` is safe to call before the map is laid out; flutter_map queues
    // the move and applies it on the first frame.
    _mapController.move(point, _kFocusZoom);
  }

  @override
  Widget build(BuildContext context) {
    final origin = ref.watch(currentLocationProvider).maybeWhen(
          data: (p) => p,
          orElse: () => kDefaultMapCenter,
        );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Plan route')),
      body: Column(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlaceSearchField(
                  controller: _searchController,
                  hintText: 'Hedef yer ara (örn: Beşiktaş İskele)',
                  bias: _kBesiktasBias,
                  onSelected: _onPlaceSelected,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _destination == null
                            ? 'Veya haritaya dokunun'
                            : 'Destination set — ready to find routes.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: origin,
                initialZoom: kDefaultZoom,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.evam.saferoute',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: origin,
                      child: const Icon(Icons.my_location, color: Colors.blue),
                    ),
                    if (_destination != null)
                      Marker(
                        width: 40,
                        height: 40,
                        point: _destination!,
                        child: const Icon(Icons.place,
                            color: Colors.red, size: 36),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.directions),
        label: const Text('Find route'),
        onPressed: _destination == null
            ? null
            : () => context.push(
                  '/route/detail',
                  extra: RouteRequest(
                    from: origin,
                    to: _destination!,
                    time: DateTime.now(),
                  ),
                ),
      ),
    );
  }
}

/// Cross-screen payload — passed via go_router `extra`.
class RouteRequest {
  const RouteRequest({
    required this.from,
    required this.to,
    required this.time,
  });

  final LatLng from;
  final LatLng to;
  final DateTime time;
}
