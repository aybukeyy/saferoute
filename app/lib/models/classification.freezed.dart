// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'classification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Classification {

 ReportCategory get category; RiskLevel get riskLevel; bool get timeSensitive; double get confidence; String get explanation; bool get needsReview;
/// Create a copy of Classification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClassificationCopyWith<Classification> get copyWith => _$ClassificationCopyWithImpl<Classification>(this as Classification, _$identity);

  /// Serializes this Classification to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Classification&&(identical(other.category, category) || other.category == category)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&(identical(other.timeSensitive, timeSensitive) || other.timeSensitive == timeSensitive)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.needsReview, needsReview) || other.needsReview == needsReview));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,category,riskLevel,timeSensitive,confidence,explanation,needsReview);

@override
String toString() {
  return 'Classification(category: $category, riskLevel: $riskLevel, timeSensitive: $timeSensitive, confidence: $confidence, explanation: $explanation, needsReview: $needsReview)';
}


}

/// @nodoc
abstract mixin class $ClassificationCopyWith<$Res>  {
  factory $ClassificationCopyWith(Classification value, $Res Function(Classification) _then) = _$ClassificationCopyWithImpl;
@useResult
$Res call({
 ReportCategory category, RiskLevel riskLevel, bool timeSensitive, double confidence, String explanation, bool needsReview
});




}
/// @nodoc
class _$ClassificationCopyWithImpl<$Res>
    implements $ClassificationCopyWith<$Res> {
  _$ClassificationCopyWithImpl(this._self, this._then);

  final Classification _self;
  final $Res Function(Classification) _then;

/// Create a copy of Classification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? category = null,Object? riskLevel = null,Object? timeSensitive = null,Object? confidence = null,Object? explanation = null,Object? needsReview = null,}) {
  return _then(_self.copyWith(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ReportCategory,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as RiskLevel,timeSensitive: null == timeSensitive ? _self.timeSensitive : timeSensitive // ignore: cast_nullable_to_non_nullable
as bool,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,needsReview: null == needsReview ? _self.needsReview : needsReview // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Classification].
extension ClassificationPatterns on Classification {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Classification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Classification() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Classification value)  $default,){
final _that = this;
switch (_that) {
case _Classification():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Classification value)?  $default,){
final _that = this;
switch (_that) {
case _Classification() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReportCategory category,  RiskLevel riskLevel,  bool timeSensitive,  double confidence,  String explanation,  bool needsReview)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Classification() when $default != null:
return $default(_that.category,_that.riskLevel,_that.timeSensitive,_that.confidence,_that.explanation,_that.needsReview);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReportCategory category,  RiskLevel riskLevel,  bool timeSensitive,  double confidence,  String explanation,  bool needsReview)  $default,) {final _that = this;
switch (_that) {
case _Classification():
return $default(_that.category,_that.riskLevel,_that.timeSensitive,_that.confidence,_that.explanation,_that.needsReview);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReportCategory category,  RiskLevel riskLevel,  bool timeSensitive,  double confidence,  String explanation,  bool needsReview)?  $default,) {final _that = this;
switch (_that) {
case _Classification() when $default != null:
return $default(_that.category,_that.riskLevel,_that.timeSensitive,_that.confidence,_that.explanation,_that.needsReview);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Classification implements Classification {
  const _Classification({required this.category, required this.riskLevel, required this.timeSensitive, required this.confidence, required this.explanation, this.needsReview = false});
  factory _Classification.fromJson(Map<String, dynamic> json) => _$ClassificationFromJson(json);

@override final  ReportCategory category;
@override final  RiskLevel riskLevel;
@override final  bool timeSensitive;
@override final  double confidence;
@override final  String explanation;
@override@JsonKey() final  bool needsReview;

/// Create a copy of Classification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClassificationCopyWith<_Classification> get copyWith => __$ClassificationCopyWithImpl<_Classification>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ClassificationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Classification&&(identical(other.category, category) || other.category == category)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&(identical(other.timeSensitive, timeSensitive) || other.timeSensitive == timeSensitive)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.needsReview, needsReview) || other.needsReview == needsReview));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,category,riskLevel,timeSensitive,confidence,explanation,needsReview);

@override
String toString() {
  return 'Classification(category: $category, riskLevel: $riskLevel, timeSensitive: $timeSensitive, confidence: $confidence, explanation: $explanation, needsReview: $needsReview)';
}


}

/// @nodoc
abstract mixin class _$ClassificationCopyWith<$Res> implements $ClassificationCopyWith<$Res> {
  factory _$ClassificationCopyWith(_Classification value, $Res Function(_Classification) _then) = __$ClassificationCopyWithImpl;
@override @useResult
$Res call({
 ReportCategory category, RiskLevel riskLevel, bool timeSensitive, double confidence, String explanation, bool needsReview
});




}
/// @nodoc
class __$ClassificationCopyWithImpl<$Res>
    implements _$ClassificationCopyWith<$Res> {
  __$ClassificationCopyWithImpl(this._self, this._then);

  final _Classification _self;
  final $Res Function(_Classification) _then;

/// Create a copy of Classification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? category = null,Object? riskLevel = null,Object? timeSensitive = null,Object? confidence = null,Object? explanation = null,Object? needsReview = null,}) {
  return _then(_Classification(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ReportCategory,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as RiskLevel,timeSensitive: null == timeSensitive ? _self.timeSensitive : timeSensitive // ignore: cast_nullable_to_non_nullable
as bool,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,needsReview: null == needsReview ? _self.needsReview : needsReview // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
