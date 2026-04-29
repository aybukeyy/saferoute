import 'package:freezed_annotation/freezed_annotation.dart';

import 'report.dart';

part 'classification.freezed.dart';
part 'classification.g.dart';

/// Output of Gemma 4 E2B's per-report classification call. Maps directly to
/// the locked JSON schema in docs/planning/IMPLEMENTATION.md §3.
///
/// `needsReview` is set by the parser (not the model) when JSON parsing falls
/// through to the safe default twice — see ai/parser.dart.
@freezed
abstract class Classification with _$Classification {
  const factory Classification({
    required ReportCategory category,
    required RiskLevel riskLevel,
    required bool timeSensitive,
    required double confidence,
    required String explanation,
    @Default(false) bool needsReview,
  }) = _Classification;

  factory Classification.fromJson(Map<String, dynamic> json) =>
      _$ClassificationFromJson(json);
}
