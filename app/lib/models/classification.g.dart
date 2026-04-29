// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'classification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Classification _$ClassificationFromJson(Map<String, dynamic> json) =>
    _Classification(
      category: $enumDecode(_$ReportCategoryEnumMap, json['category']),
      riskLevel: $enumDecode(_$RiskLevelEnumMap, json['riskLevel']),
      timeSensitive: json['timeSensitive'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      explanation: json['explanation'] as String,
      needsReview: json['needsReview'] as bool? ?? false,
    );

Map<String, dynamic> _$ClassificationToJson(_Classification instance) =>
    <String, dynamic>{
      'category': _$ReportCategoryEnumMap[instance.category]!,
      'riskLevel': _$RiskLevelEnumMap[instance.riskLevel]!,
      'timeSensitive': instance.timeSensitive,
      'confidence': instance.confidence,
      'explanation': instance.explanation,
      'needsReview': instance.needsReview,
    };

const _$ReportCategoryEnumMap = {
  ReportCategory.violence: 'violence',
  ReportCategory.theft: 'theft',
  ReportCategory.harassment: 'harassment',
  ReportCategory.suspiciousActivity: 'suspicious_activity',
  ReportCategory.vandalism: 'vandalism',
  ReportCategory.other: 'other',
};

const _$RiskLevelEnumMap = {
  RiskLevel.low: 'low',
  RiskLevel.medium: 'medium',
  RiskLevel.high: 'high',
};
