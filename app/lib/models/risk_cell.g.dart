// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'risk_cell.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RiskCell _$RiskCellFromJson(Map<String, dynamic> json) => _RiskCell(
  geohash7: json['geohash7'] as String,
  score: (json['score'] as num).toDouble(),
  topCategory: $enumDecodeNullable(
    _$ReportCategoryEnumMap,
    json['topCategory'],
  ),
  reportCount: (json['reportCount'] as num).toInt(),
  summary: json['summary'] as String?,
  summaryAt: json['summaryAt'] == null
      ? null
      : DateTime.parse(json['summaryAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$RiskCellToJson(_RiskCell instance) => <String, dynamic>{
  'geohash7': instance.geohash7,
  'score': instance.score,
  'topCategory': _$ReportCategoryEnumMap[instance.topCategory],
  'reportCount': instance.reportCount,
  'summary': instance.summary,
  'summaryAt': instance.summaryAt?.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$ReportCategoryEnumMap = {
  ReportCategory.violence: 'violence',
  ReportCategory.theft: 'theft',
  ReportCategory.harassment: 'harassment',
  ReportCategory.suspiciousActivity: 'suspicious_activity',
  ReportCategory.vandalism: 'vandalism',
  ReportCategory.other: 'other',
};
