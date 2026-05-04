import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import 'emergency_action.dart';

class EmergencyFab extends ConsumerStatefulWidget {
  const EmergencyFab({
    super.key,
    required this.actionBuilder,
    this.holdDuration = const Duration(milliseconds: 1000),
  });

  final Future<EmergencyAction> Function() actionBuilder;
  final Duration holdDuration;

  @override
  ConsumerState<EmergencyFab> createState() => _EmergencyFabState();
}

class _EmergencyFabState extends ConsumerState<EmergencyFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  );
  bool _firing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    _ctrl.forward(from: 0);
  }

  void _onTapCancel() {
    _ctrl.reverse();
  }

  Future<void> _onLongPress() async {
    if (_firing) return;
    setState(() => _firing = true);
    final strings = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final action = await widget.actionBuilder();
      await action.trigger();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.emergencySent),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e, st) {
      debugPrint('[emergency] trigger failed: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.emergencyError('$e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _firing = false);
        _ctrl.reverse();
      }
    }
  }

  void _onShortTap() {
    final strings = ref.read(stringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.emergencyHoldHint),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onShortTap,
      onTapDown: _onTapDown,
      onTapCancel: _onTapCancel,
      onLongPressStart: (_) => _ctrl.forward(from: 0),
      onLongPressEnd: (_) => _ctrl.reverse(),
      onLongPress: _onLongPress,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: _ctrl.value == 0 ? 0 : _ctrl.value,
                  strokeWidth: 4,
                  color: Colors.white,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            IgnorePointer(
              child: FloatingActionButton(
                heroTag: 'fab-emergency',
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                tooltip: 'Acil durum / Emergency',
                onPressed: () {},
                child: _firing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.warning_amber_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
