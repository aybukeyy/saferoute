// Reusable typeahead field for picking a place by name. Wraps a
// Material 3 `TextField` (we deliberately don't use `SearchAnchor` /
// `SearchBar` here — the latter pushes a full-screen overlay which fights
// the half-screen map UX we want on the route planner).
//
// Behaviour:
//   * `onChanged` schedules a 300 ms debounced lookup against
//     [PlaceSearchService] — well clear of Nominatim's 1 req/sec/IP cap
//     even for a fast typist.
//   * Queries shorter than 3 characters are ignored client-side so we don't
//     waste a request on a single noisy keystroke.
//   * In-flight requests show a tiny spinner suffix; selecting a result
//     fills the field with `displayName` and collapses the dropdown.
//   * The dropdown is rendered inline (a `Card` directly under the input)
//     rather than via an `OverlayEntry` — keeps focus + theming simple and
//     it's all that's needed for the demo screen layout.
//
// The widget is fully theme-aware: it reads `colorScheme` from the ambient
// theme so the search box automatically matches the app's emerald seed
// colour from `lib/app/theme.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'place_search.dart';

/// Bias rectangle for [PlaceSearchField]. Positional records keep the call
/// site short while staying explicit about which corner is which.
typedef PlaceSearchBias = ({
  double minLng,
  double minLat,
  double maxLng,
  double maxLat,
});

class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.onSelected,
    this.hintText = 'Hedef yer ara',
    this.bias,
    this.controller,
    this.debounce = const Duration(milliseconds: 300),
  });

  /// Called with the user-picked result. The widget already handles filling
  /// the text field and closing the dropdown; the parent only needs to react
  /// (e.g. animate the map, drop a marker).
  final ValueChanged<PlaceSearchResult> onSelected;

  /// Placeholder text. Defaults to a short Turkish prompt; the route planner
  /// passes a richer `"Hedef yer ara (örn: Beşiktaş İskele)"` variant.
  final String hintText;

  /// Optional bias rectangle to prefer local results without strictly
  /// excluding hits outside it (Nominatim `viewbox` without `bounded=1`).
  final PlaceSearchBias? bias;

  /// Optionally provide an external controller so the parent can clear the
  /// field (e.g. when the user picks a destination by tapping the map).
  final TextEditingController? controller;

  final Duration debounce;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounceTimer;

  /// Monotonically incremented per query so a slow earlier response can't
  /// overwrite the result list of a newer query.
  int _queryEpoch = 0;

  List<PlaceSearchResult> _results = const [];
  bool _loading = false;

  /// `true` after a successful tap on a result; suppresses the dropdown
  /// re-opening from the controller listener that fires when we set the text
  /// programmatically.
  bool _justSelected = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_handleControllerChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    // External clear (parent sets `controller.text = ''`) → drop suggestions.
    if (_controller.text.isEmpty) {
      _debounceTimer?.cancel();
      if (_results.isNotEmpty || _loading) {
        setState(() {
          _results = const [];
          _loading = false;
        });
      }
    }
  }

  void _onChanged(String value) {
    if (_justSelected) {
      // Programmatic fill from a tap — don't re-trigger a search.
      _justSelected = false;
      return;
    }

    _debounceTimer?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }

    _debounceTimer = Timer(widget.debounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final epoch = ++_queryEpoch;
    if (mounted) setState(() => _loading = true);

    final service = ref.read(placeSearchServiceProvider);
    final bias = widget.bias;
    final results = await service.search(
      query: query,
      viewboxMinLng: bias?.minLng,
      viewboxMinLat: bias?.minLat,
      viewboxMaxLng: bias?.maxLng,
      viewboxMaxLat: bias?.maxLat,
    );

    // Stale response — newer query already in flight; ignore.
    if (!mounted || epoch != _queryEpoch) return;

    setState(() {
      _results = results;
      _loading = false;
    });

    if (results.isEmpty) {
      // Best-effort hint about the rate limit. Silent on plain "no hits".
      // We can't distinguish them perfectly; only show this if the field is
      // still focused so we don't surprise the user mid-tap.
      // (No SnackBar here — too noisy for a typeahead.)
    }
  }

  void _handleSelected(PlaceSearchResult result) {
    _justSelected = true;
    _controller
      ..text = result.displayName
      ..selection = TextSelection.collapsed(offset: result.displayName.length);
    setState(() {
      _results = const [];
      _loading = false;
    });
    _focus.unfocus();
    widget.onSelected(result);
  }

  void _clear() {
    _justSelected = false;
    _controller.clear();
    setState(() {
      _results = const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showDropdown = _results.isNotEmpty;
    final hasText = _controller.text.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buildSuffix(hasText: hasText),
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        if (showDropdown)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _results.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _iconForType(result.type),
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        result.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _handleSelected(result),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildSuffix({required bool hasText}) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (hasText) {
      return IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Temizle',
        onPressed: _clear,
      );
    }
    return null;
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'amenity':
        return Icons.local_cafe_outlined;
      case 'tourism':
        return Icons.attractions_outlined;
      case 'highway':
      case 'street':
        return Icons.alt_route;
      case 'building':
        return Icons.apartment;
      case 'place':
        return Icons.place_outlined;
      default:
        return Icons.location_on_outlined;
    }
  }
}
