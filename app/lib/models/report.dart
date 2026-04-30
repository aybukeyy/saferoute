import 'package:freezed_annotation/freezed_annotation.dart';

part 'report.freezed.dart';
part 'report.g.dart';

/// Category bucket emitted by Gemma 4 E2B classification.
/// Mirrors the SQLite `reports.category` column. Source of truth:
/// docs/planning/IMPLEMENTATION.md §3 (locked classification prompt schema).
enum ReportCategory {
  @JsonValue('violence')
  violence,
  @JsonValue('theft')
  theft,
  @JsonValue('harassment')
  harassment,
  @JsonValue('suspicious_activity')
  suspiciousActivity,
  @JsonValue('vandalism')
  vandalism,
  @JsonValue('other')
  other,
}

/// Risk level emitted by Gemma 4 E2B classification.
/// `high` is reserved for active or recent (<1h) physical danger.
enum RiskLevel {
  @JsonValue('low')
  low,
  @JsonValue('medium')
  medium,
  @JsonValue('high')
  high,
}

/// Lifecycle of a report row in the local SQLite store.
/// Pending  -> just submitted, not yet classified.
/// Classified -> Gemma populated category/risk/explanation.
/// Rejected -> safety override (e.g. parser failed twice; needs review).
/// Failed -> classification threw before producing a result.
enum ReportStatus {
  @JsonValue('PENDING')
  pending,
  @JsonValue('CLASSIFIED')
  classified,
  @JsonValue('REJECTED')
  rejected,
  @JsonValue('FAILED')
  failed,
}

@freezed
abstract class Report with _$Report {
  const factory Report({
    required String id,
    required String uid,
    required String text,
    required double lat,
    required double lng,
    required String geohash7,
    required DateTime occurredAt,
    ReportCategory? category,
    RiskLevel? riskLevel,
    double? confidence,
    String? explanation,
    @Default(ReportStatus.pending) ReportStatus status,
    @Default(false) bool synced,
    required DateTime createdAt,
  }) = _Report;

  factory Report.fromJson(Map<String, dynamic> json) => _$ReportFromJson(json);
}
