// RecentReportsScreen — flat list of the last N reports for the
// "neighborhood activity" tab. Lightweight; the heavy storytelling lives
// in MapScreen and ExplanationCard.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../models/report.dart';
import '../providers.dart';

class RecentReportsScreen extends ConsumerWidget {
  const RecentReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReports = ref.watch(recentReportsProvider);
    final strings = ref.watch(stringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.recentTitle)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentReportsProvider),
        child: asyncReports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(strings.recentFailed('$e'))),
          data: (reports) {
            if (reports.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text(strings.recentEmpty)),
                ],
              );
            }
            return ListView.separated(
              itemCount: reports.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _ReportRow(report: reports[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('MMM d · HH:mm').format(report.occurredAt.toLocal());
    final isPending = report.status == ReportStatus.pending;
    return ListTile(
      leading: Icon(
        isPending ? Icons.hourglass_empty : Icons.shield_outlined,
        color: isPending
            ? Colors.grey
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(report.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${report.category?.name ?? 'unclassified'} · ${report.riskLevel?.name ?? '—'} · $time',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
