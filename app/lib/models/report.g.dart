// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Report _$ReportFromJson(Map<String, dynamic> json) => _Report(
  id: json['id'] as String,
  uid: json['uid'] as String,
  text: json['text'] as String,
  lat: (json['lat'] as num).toDouble(),
  lng: (json['lng'] as num).toDouble(),
  geohash7: json['geohash7'] as String,
  occurredAt: DateTime.parse(json['occurredAt'] as String),
  category: $enumDecodeNullable(_$ReportCategoryEnumMap, json['category']),
  riskLevel: $enumDecodeNullable(_$RiskLevelEnumMap, json['riskLevel']),
  confidence: (json['confidence'] as num?)?.toDouble(),
  explanation: json['explanation'] as String?,
  status:
      $enumDecodeNullable(_$ReportStatusEnumMap, json['status']) ??
      ReportStatus.pending,
  synced: json['synced'] as bool? ?? false,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ReportToJson(_Report instance) => <String, dynamic>{
  'id': instance.id,
  'uid': instance.uid,
  'text': instance.text,
  'lat': instance.lat,
  'lng': instance.lng,
  'geohash7': instance.geohash7,
  'occurredAt': instance.occurredAt.toIso8601String(),
  'category': _$ReportCategoryEnumMap[instance.category],
  'riskLevel': _$RiskLevelEnumMap[instance.riskLevel],
  'confidence': instance.confidence,
  'explanation': instance.explanation,
  'status': _$ReportStatusEnumMap[instance.status]!,
  'synced': instance.synced,
  'createdAt': instance.createdAt.toIso8601String(),
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

const _$ReportStatusEnumMap = {
  ReportStatus.pending: 'PENDING',
  ReportStatus.classified: 'CLASSIFIED',
  ReportStatus.rejected: 'REJECTED',
};
