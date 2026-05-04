// Route-share UX: AppBar IconButton → message dialog → live position
// broadcast for the lifetime of `RouteDetailScreen`. The owner taps "End
// share" (or leaves the screen) and we mark the doc ended.
//
// All Firestore work goes through `RouteShareService`; this file is just
// glue + UI.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/real_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/route_share_service.dart';
import '../../models/route_result.dart';
import '../providers.dart';
import 'route_planner_screen.dart';

/// Public deep-link prefix. The path-only fallback (`saferoute://share/<id>`)
/// also resolves via the platform deep-link config. The shared text shows the
/// HTTPS form because it's tappable in every messaging app.
const String kRouteShareLinkPrefix = 'https://saferoute.app/share/';

/// AppBar IconButton that owns the share session lifecycle. Drop into
/// `actions:` of `RouteDetailScreen`'s AppBar.
class RouteShareControl extends ConsumerStatefulWidget {
  const RouteShareControl({
    super.key,
    required this.request,
    required this.result,
  });

  final RouteRequest request;
  final RouteResult result;

  @override
  ConsumerState<RouteShareControl> createState() => _RouteShareControlState();
}

class _RouteShareControlState extends ConsumerState<RouteShareControl> {
  _SharingState _state = const _Idle();
  Timer? _pushTimer;
  StreamSubscription<LatLng>? _positionSub;
  LatLng? _lastPosition;

  @override
  void dispose() {
    _stopBroadcast();
    super.dispose();
  }

  void _stopBroadcast() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _onTap() async {
    final state = _state;
    if (state is _Active) {
      await _confirmEnd(state);
      return;
    }
    await _openComposeDialog();
  }

  Future<void> _openComposeDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final etaMinutes = (widget.result.explanationCard.timeDeltaSeconds / 60)
        .clamp(0, double.infinity)
        .round();
    final defaultMessage =
        etaMinutes > 0 ? 'Eve dönüyorum, $etaMinutes dk.' : 'Eve dönüyorum.';
    final message = await showDialog<String?>(
      context: context,
      builder: (ctx) => _ComposeDialog(initialMessage: defaultMessage),
    );
    if (message == null || !mounted) return;
    setState(() => _state = const _Starting());

    final svcAsync = ref.read(routeShareServiceProvider);
    final svc = svcAsync.maybeWhen(
      data: (s) => s,
      orElse: () => null,
    );
    if (svc == null || !svc.isEnabled) {
      if (!mounted) return;
      setState(() => _state = const _Idle());
      final strings = ref.read(stringsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.shareOffline)),
      );
      return;
    }

    final uid = ref.read(currentUserUidValueProvider);
    final startPos = _lastPosition ?? widget.request.from;
    final eta = _estimatedEtaMinutes(widget.result, etaMinutes);

    final share = await svc.create(
      ownerUid: uid,
      from: widget.request.from,
      to: widget.request.to,
      safestPath: widget.result.safestPath,
      etaMinutes: eta,
      startPosition: startPos,
      message: message.trim().isEmpty ? null : message.trim(),
    );

    if (!mounted) return;
    if (share == null) {
      setState(() => _state = const _Idle());
      final strings = ref.read(stringsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.shareCouldNotStart)),
      );
      return;
    }

    setState(() => _state = _Active(shareId: share.id, message: message));
    _startBroadcast(svc, share.id);
    await _shareOutbound(share.id, message);
  }

  void _startBroadcast(RouteShareService svc, String shareId) {
    _positionSub = ref
        .read(locationServiceProvider)
        .watchPosition()
        .listen((p) => _lastPosition = p);
    _pushTimer = Timer.periodic(
      kRouteSharePositionPushInterval,
      (_) {
        final p = _lastPosition;
        if (p == null) return;
        unawaited(svc.updatePosition(shareId: shareId, position: p));
      },
    );
  }

  Future<void> _shareOutbound(String shareId, String message) async {
    final url = '$kRouteShareLinkPrefix$shareId';
    final body = '$message\n\n$url';
    try {
      await Share.share(body, subject: 'Safe Route');
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: body));
      if (!mounted) return;
      final strings = ref.read(stringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.shareLinkCopied)),
      );
    }
  }

  Future<void> _confirmEnd(_Active state) async {
    final strings = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.shareEndDialogTitle),
        content: Text(strings.shareEndDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.shareCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.shareEnd),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _stopBroadcast();

    final svcAsync = ref.read(routeShareServiceProvider);
    final svc = svcAsync.maybeWhen(
      data: (s) => s,
      orElse: () => null,
    );
    if (svc != null) await svc.end(state.shareId);
    if (!mounted) return;
    setState(() => _state = const _Idle());
    messenger.showSnackBar(
      SnackBar(content: Text(strings.shareEnded)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final icon = switch (state) {
      _Active() => Icons.share,
      _Starting() => Icons.hourglass_top,
      _Idle() => Icons.share_outlined,
    };
    final color = state is _Active
        ? Theme.of(context).colorScheme.primary
        : null;
    final strings = ref.watch(stringsProvider);
    final tooltip = state is _Active
        ? '${strings.shareEnd} · ${strings.shareDialogTitle}'
        : strings.shareDialogTitle;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: state is _Starting ? null : _onTap,
    );
  }
}

class _ComposeDialog extends ConsumerStatefulWidget {
  const _ComposeDialog({required this.initialMessage});

  final String initialMessage;

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialMessage);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return AlertDialog(
      title: Text(strings.shareDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.shareDialogHint),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: strings.shareMessageLabel,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(strings.shareCancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          label: Text(strings.shareAction),
        ),
      ],
    );
  }
}

int _estimatedEtaMinutes(RouteResult result, int extraFromExplanation) {
  final path = result.safestPath;
  if (path.length < 2) return extraFromExplanation;
  var meters = 0.0;
  for (var i = 0; i + 1 < path.length; i++) {
    meters += _haversine(path[i], path[i + 1]);
  }
  // Walking pace constant — matches what the planner shows the user.
  const metersPerMinute = 5000.0 / 60.0;
  final base = (meters / metersPerMinute).round();
  return base + extraFromExplanation;
}

double _haversine(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

sealed class _SharingState {
  const _SharingState();
}

class _Idle extends _SharingState {
  const _Idle();
}

class _Starting extends _SharingState {
  const _Starting();
}

class _Active extends _SharingState {
  const _Active({required this.shareId, required this.message});
  final String shareId;
  final String message;
}
