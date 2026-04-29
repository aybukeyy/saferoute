// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'risk_cell.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RiskCell {

 String get geohash7; double get score; ReportCategory? get topCategory; int get reportCount; String? get summary; DateTime? get summaryAt; DateTime get updatedAt;
/// Create a copy of RiskCell
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RiskCellCopyWith<RiskCell> get copyWith => _$RiskCellCopyWithImpl<RiskCell>(this as RiskCell, _$identity);

  /// Serializes this RiskCell to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RiskCell&&(identical(other.geohash7, geohash7) || other.geohash7 == geohash7)&&(identical(other.score, score) || other.score == score)&&(identical(other.topCategory, topCategory) || other.topCategory == topCategory)&&(identical(other.reportCount, reportCount) || other.reportCount == reportCount)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryAt, summaryAt) || other.summaryAt == summaryAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,geohash7,score,topCategory,reportCount,summary,summaryAt,updatedAt);

@override
String toString() {
  return 'RiskCell(geohash7: $geohash7, score: $score, topCategory: $topCategory, reportCount: $reportCount, summary: $summary, summaryAt: $summaryAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $RiskCellCopyWith<$Res>  {
  factory $RiskCellCopyWith(RiskCell value, $Res Function(RiskCell) _then) = _$RiskCellCopyWithImpl;
@useResult
$Res call({
 String geohash7, double score, ReportCategory? topCategory, int reportCount, String? summary, DateTime? summaryAt, DateTime updatedAt
});




}
/// @nodoc
class _$RiskCellCopyWithImpl<$Res>
    implements $RiskCellCopyWith<$Res> {
  _$RiskCellCopyWithImpl(this._self, this._then);

  final RiskCell _self;
  final $Res Function(RiskCell) _then;

/// Create a copy of RiskCell
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? geohash7 = null,Object? score = null,Object? topCategory = freezed,Object? reportCount = null,Object? summary = freezed,Object? summaryAt = freezed,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
geohash7: null == geohash7 ? _self.geohash7 : geohash7 // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,topCategory: freezed == topCategory ? _self.topCategory : topCategory // ignore: cast_nullable_to_non_nullable
as ReportCategory?,reportCount: null == reportCount ? _self.reportCount : reportCount // ignore: cast_nullable_to_non_nullable
as int,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,summaryAt: freezed == summaryAt ? _self.summaryAt : summaryAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [RiskCell].
extension RiskCellPatterns on RiskCell {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RiskCell value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RiskCell() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RiskCell value)  $default,){
final _that = this;
switch (_that) {
case _RiskCell():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RiskCell value)?  $default,){
final _that = this;
switch (_that) {
case _RiskCell() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String geohash7,  double score,  ReportCategory? topCategory,  int reportCount,  String? summary,  DateTime? summaryAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RiskCell() when $default != null:
return $default(_that.geohash7,_that.score,_that.topCategory,_that.reportCount,_that.summary,_that.summaryAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String geohash7,  double score,  ReportCategory? topCategory,  int reportCount,  String? summary,  DateTime? summaryAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _RiskCell():
return $default(_that.geohash7,_that.score,_that.topCategory,_that.reportCount,_that.summary,_that.summaryAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String geohash7,  double score,  ReportCategory? topCategory,  int reportCount,  String? summary,  DateTime? summaryAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _RiskCell() when $default != null:
return $default(_that.geohash7,_that.score,_that.topCategory,_that.reportCount,_that.summary,_that.summaryAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RiskCell implements RiskCell {
  const _RiskCell({required this.geohash7, required this.score, this.topCategory, required this.reportCount, this.summary, this.summaryAt, required this.updatedAt});
  factory _RiskCell.fromJson(Map<String, dynamic> json) => _$RiskCellFromJson(json);

@override final  String geohash7;
@override final  double score;
@override final  ReportCategory? topCategory;
@override final  int reportCount;
@override final  String? summary;
@override final  DateTime? summaryAt;
@override final  DateTime updatedAt;

/// Create a copy of RiskCell
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RiskCellCopyWith<_RiskCell> get copyWith => __$RiskCellCopyWithImpl<_RiskCell>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RiskCellToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RiskCell&&(identical(other.geohash7, geohash7) || other.geohash7 == geohash7)&&(identical(other.score, score) || other.score == score)&&(identical(other.topCategory, topCategory) || other.topCategory == topCategory)&&(identical(other.reportCount, reportCount) || other.reportCount == reportCount)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryAt, summaryAt) || other.summaryAt == summaryAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,geohash7,score,topCategory,reportCount,summary,summaryAt,updatedAt);

@override
String toString() {
  return 'RiskCell(geohash7: $geohash7, score: $score, topCategory: $topCategory, reportCount: $reportCount, summary: $summary, summaryAt: $summaryAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$RiskCellCopyWith<$Res> implements $RiskCellCopyWith<$Res> {
  factory _$RiskCellCopyWith(_RiskCell value, $Res Function(_RiskCell) _then) = __$RiskCellCopyWithImpl;
@override @useResult
$Res call({
 String geohash7, double score, ReportCategory? topCategory, int reportCount, String? summary, DateTime? summaryAt, DateTime updatedAt
});




}
/// @nodoc
class __$RiskCellCopyWithImpl<$Res>
    implements _$RiskCellCopyWith<$Res> {
  __$RiskCellCopyWithImpl(this._self, this._then);

  final _RiskCell _self;
  final $Res Function(_RiskCell) _then;

/// Create a copy of RiskCell
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? geohash7 = null,Object? score = null,Object? topCategory = freezed,Object? reportCount = null,Object? summary = freezed,Object? summaryAt = freezed,Object? updatedAt = null,}) {
  return _then(_RiskCell(
geohash7: null == geohash7 ? _self.geohash7 : geohash7 // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,topCategory: freezed == topCategory ? _self.topCategory : topCategory // ignore: cast_nullable_to_non_nullable
as ReportCategory?,reportCount: null == reportCount ? _self.reportCount : reportCount // ignore: cast_nullable_to_non_nullable
as int,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,summaryAt: freezed == summaryAt ? _self.summaryAt : summaryAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
