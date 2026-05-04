// ExplanationCard — three-layer explainable AI panel.
//
// Submission angle: this card is the project's pitch into the **Safety &
// Trust** impact track (ARCHITECTURE.md §7). The three layers are:
//
//   Layer 1 — Route-level. Gemma 4 E4B summary sentence + factor chips
//             (avoided cell, night, surge, trade-off).
//   Layer 2 — Report-level. Tap an avoided cell → sheet of contributing
//             reports with the user's text + Gemma 4 E2B explanation.
//   Layer 3 — Temporal multipliers, verbatim. The exact formula the risk
//             engine uses, in words: "Risk = base × 1.5 (night) × 2.0
//             (surge)". Numbers come from RiskEngine, never hard-coded.
//
// The text never says "the AI thinks". It quotes the data and the model.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../models/report.dart';
import '../../models/route_result.dart';
import '../providers.dart';

class ExplanationCard extends ConsumerWidget {
  const ExplanationCard({super.key, required this.result});

  final RouteResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exp = result.explanationCard;
    final strings = ref.watch(stringsProvider);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.routeWhyIsThisSafer,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            // Layer 1 — Gemma 4 E4B route-level summary
            if (exp.gemmaSummary != null)
              Text(exp.gemmaSummary!,
                  style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),

            // Factor chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FactorChip(
                  emoji: '🚫',
                  label: '${exp.avoidedCellSummaries.length} avoided cell'
                      '${exp.avoidedCellSummaries.length == 1 ? '' : 's'}'
                      ' — recent reports',
                ),
                _FactorChip(
                  emoji: '🌙',
                  label: 'Night ×${_fmt(exp.nightMultiplier)} active',
                ),
                _FactorChip(
                  emoji: '📈',
                  label: 'Surge ×${_fmt(exp.surgeMultiplier)} (recent activity)',
                ),
                _FactorChip(
                  emoji: '➕',
                  label: '+${exp.distanceDeltaMeters.round()} m, '
                      '+${(exp.timeDeltaSeconds / 60).round()} min',
                ),
              ],
            ),
            const Divider(height: 32),

            // Layer 2 — per-cell tap-able sheets
            Text(strings.explainAvoidedCells,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final cell in result.avoidedCells)
              _AvoidedCellTile(geohash7: cell, label: exp.avoidedCellSummaries[cell]),

            const Divider(height: 32),

            // Layer 3 — verbatim formula
            Text(strings.explainRiskFormula,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Risk = base × ${_fmt(exp.nightMultiplier)} (night) '
                '× ${_fmt(exp.surgeMultiplier)} (surge)',
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Multipliers come straight from the local risk engine, not '
              'from an opaque model. Tap a cell above for the contributing '
              'reports.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }
}

class _FactorChip extends StatelessWidget {
  const _FactorChip({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AvoidedCellTile extends ConsumerWidget {
  const _AvoidedCellTile({required this.geohash7, required this.label});

  final String geohash7;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.warning_amber, color: Colors.red),
        title: Text(label ?? geohash7),
        subtitle: Text('Cell $geohash7 — tap for contributing reports'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => CellReportsSheet(geohash7: geohash7),
          );
        },
      ),
    );
  }
}

class CellReportsSheet extends ConsumerWidget {
  const CellReportsSheet({super.key, required this.geohash7});

  final String geohash7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsInCellProvider(geohash7));
    final summaryAsync = ref.watch(cellAreaSummaryProvider(geohash7));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reports in this cell',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Cell $geohash7',
                style: Theme.of(context).textTheme.bodySmall),
            _AreaSummaryHeader(summary: summaryAsync),
            const SizedBox(height: 16),
            reportsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Failed to load reports: $e'),
              data: (reports) {
                if (reports.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No contributing reports in this cell yet.'),
                  );
                }
                return Column(
                  children: [
                    for (final r in reports) _ReportTile(report: r),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaSummaryHeader extends StatelessWidget {
  const _AreaSummaryHeader({required this.summary});

  final AsyncValue<String> summary;

  @override
  Widget build(BuildContext context) {
    return summary.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Generating area summary…'),
            ],
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (text) {
        final trimmed = text.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trimmed,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
            ],
          ),
        );
      },
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('MMM d · HH:mm').format(report.occurredAt.toLocal());
    final levelColor = switch (report.riskLevel) {
      RiskLevel.high => Colors.red,
      RiskLevel.medium => Colors.orange,
      RiskLevel.low => Colors.amber,
      _ => Colors.grey,
    };

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: levelColor, width: 1),
              ),
              child: Text(
                (report.riskLevel?.name ?? 'unknown').toUpperCase(),
                style: TextStyle(
                    color: levelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text(report.category?.name ?? '—',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(time, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Text('“${report.text}”',
            style: const TextStyle(fontStyle: FontStyle.italic)),
        if (report.visionSummary != null &&
            report.visionSummary!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Scene: ${report.visionSummary!}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (report.explanation != null && report.explanation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Gemma 4 E2B: ${report.explanation!}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: report.photoUrl != null && report.photoUrl!.isNotEmpty
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      report.photoUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.broken_image_outlined, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    );
  }
}
