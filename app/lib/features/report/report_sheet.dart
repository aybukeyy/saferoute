// ReportSheet — modal bottom sheet for "+ Report".
//
// One-tap, one-sentence flow per DEMO.md Scene 3. Auto-attached location
// chip (read-only in v1), 280-char free-text field, big submit button.
// Optimistic UI: on submit we close the sheet immediately and surface a
// snackbar — the actual classification continues in the background.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Convenience opener — keeps the call site in MapScreen short.
Future<void> showReportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _ReportSheet(),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet();

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type one sentence describing what you saw.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final position = await ref.read(locationServiceProvider).currentPosition();
      await ref.read(reportsRepositoryProvider).submitReport(
            text: text,
            at: position,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report received — classifying on-device…'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _humaniseError(e);
      });
    }
  }

  String _humaniseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('rate') || msg.contains('limit')) {
      return 'You\'ve hit the per-hour report limit. Try again later.';
    }
    if (msg.contains('location') || msg.contains('permission')) {
      return 'Location permission is required to attach the report.';
    }
    return 'Submission failed. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(currentLocationProvider);
    final position = positionAsync.whenOrNull(data: (p) => p);
    final padding = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New report',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _LocationChip(position: position),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 280,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(280)],
            decoration: const InputDecoration(
              hintText: 'Describe what happened in one sentence…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Sending…' : 'Submit report'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.position});

  final dynamic position;

  @override
  Widget build(BuildContext context) {
    final label = position == null
        ? 'Resolving location…'
        : '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.location_on, size: 18),
        label: Text(label),
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      ),
    );
  }
}
