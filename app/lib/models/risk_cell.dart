import 'package:freezed_annotation/freezed_annotation.dart';

import 'report.dart';

part 'risk_cell.freezed.dart';
part 'risk_cell.g.dart';

/// Per-cell aggregate risk row. One row per geohash-7 cell that has at least
/// one report. Recomputed deterministically by `RiskEngine`. Source of truth:
/// docs/planning/IMPLEMENTATION.md §4 and ARCHITECTURE.md §4-§5.
@freezed
abstract class RiskCell with _$RiskCell {
  const factory RiskCell({
    required String geohash7,
    required double score,
    ReportCategory? topCategory,
    required int reportCount,
    String? summary,
    DateTime? summaryAt,
    required DateTime updatedAt,
  }) = _RiskCell;

  factory RiskCell.fromJson(Map<String, dynamic> json) =>
      _$RiskCellFromJson(json);
}
