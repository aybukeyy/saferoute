// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'route_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RouteResult {

 List<LatLng> get shortestPath; List<LatLng> get safestPath; List<String> get avoidedCells; RouteExplanation get explanationCard;
/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RouteResultCopyWith<RouteResult> get copyWith => _$RouteResultCopyWithImpl<RouteResult>(this as RouteResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RouteResult&&const DeepCollectionEquality().equals(other.shortestPath, shortestPath)&&const DeepCollectionEquality().equals(other.safestPath, safestPath)&&const DeepCollectionEquality().equals(other.avoidedCells, avoidedCells)&&(identical(other.explanationCard, explanationCard) || other.explanationCard == explanationCard));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(shortestPath),const DeepCollectionEquality().hash(safestPath),const DeepCollectionEquality().hash(avoidedCells),explanationCard);

@override
String toString() {
  return 'RouteResult(shortestPath: $shortestPath, safestPath: $safestPath, avoidedCells: $avoidedCells, explanationCard: $explanationCard)';
}


}

/// @nodoc
abstract mixin class $RouteResultCopyWith<$Res>  {
  factory $RouteResultCopyWith(RouteResult value, $Res Function(RouteResult) _then) = _$RouteResultCopyWithImpl;
@useResult
$Res call({
 List<LatLng> shortestPath, List<LatLng> safestPath, List<String> avoidedCells, RouteExplanation explanationCard
});


$RouteExplanationCopyWith<$Res> get explanationCard;

}
/// @nodoc
class _$RouteResultCopyWithImpl<$Res>
    implements $RouteResultCopyWith<$Res> {
  _$RouteResultCopyWithImpl(this._self, this._then);

  final RouteResult _self;
  final $Res Function(RouteResult) _then;

/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shortestPath = null,Object? safestPath = null,Object? avoidedCells = null,Object? explanationCard = null,}) {
  return _then(_self.copyWith(
shortestPath: null == shortestPath ? _self.shortestPath : shortestPath // ignore: cast_nullable_to_non_nullable
as List<LatLng>,safestPath: null == safestPath ? _self.safestPath : safestPath // ignore: cast_nullable_to_non_nullable
as List<LatLng>,avoidedCells: null == avoidedCells ? _self.avoidedCells : avoidedCells // ignore: cast_nullable_to_non_nullable
as List<String>,explanationCard: null == explanationCard ? _self.explanationCard : explanationCard // ignore: cast_nullable_to_non_nullable
as RouteExplanation,
  ));
}
/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RouteExplanationCopyWith<$Res> get explanationCard {
  
  return $RouteExplanationCopyWith<$Res>(_self.explanationCard, (value) {
    return _then(_self.copyWith(explanationCard: value));
  });
}
}


/// Adds pattern-matching-related methods to [RouteResult].
extension RouteResultPatterns on RouteResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RouteResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RouteResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RouteResult value)  $default,){
final _that = this;
switch (_that) {
case _RouteResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RouteResult value)?  $default,){
final _that = this;
switch (_that) {
case _RouteResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LatLng> shortestPath,  List<LatLng> safestPath,  List<String> avoidedCells,  RouteExplanation explanationCard)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RouteResult() when $default != null:
return $default(_that.shortestPath,_that.safestPath,_that.avoidedCells,_that.explanationCard);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LatLng> shortestPath,  List<LatLng> safestPath,  List<String> avoidedCells,  RouteExplanation explanationCard)  $default,) {final _that = this;
switch (_that) {
case _RouteResult():
return $default(_that.shortestPath,_that.safestPath,_that.avoidedCells,_that.explanationCard);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LatLng> shortestPath,  List<LatLng> safestPath,  List<String> avoidedCells,  RouteExplanation explanationCard)?  $default,) {final _that = this;
switch (_that) {
case _RouteResult() when $default != null:
return $default(_that.shortestPath,_that.safestPath,_that.avoidedCells,_that.explanationCard);case _:
  return null;

}
}

}

/// @nodoc


class _RouteResult implements RouteResult {
  const _RouteResult({required final  List<LatLng> shortestPath, required final  List<LatLng> safestPath, required final  List<String> avoidedCells, required this.explanationCard}): _shortestPath = shortestPath,_safestPath = safestPath,_avoidedCells = avoidedCells;
  

 final  List<LatLng> _shortestPath;
@override List<LatLng> get shortestPath {
  if (_shortestPath is EqualUnmodifiableListView) return _shortestPath;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_shortestPath);
}

 final  List<LatLng> _safestPath;
@override List<LatLng> get safestPath {
  if (_safestPath is EqualUnmodifiableListView) return _safestPath;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_safestPath);
}

 final  List<String> _avoidedCells;
@override List<String> get avoidedCells {
  if (_avoidedCells is EqualUnmodifiableListView) return _avoidedCells;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_avoidedCells);
}

@override final  RouteExplanation explanationCard;

/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RouteResultCopyWith<_RouteResult> get copyWith => __$RouteResultCopyWithImpl<_RouteResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RouteResult&&const DeepCollectionEquality().equals(other._shortestPath, _shortestPath)&&const DeepCollectionEquality().equals(other._safestPath, _safestPath)&&const DeepCollectionEquality().equals(other._avoidedCells, _avoidedCells)&&(identical(other.explanationCard, explanationCard) || other.explanationCard == explanationCard));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_shortestPath),const DeepCollectionEquality().hash(_safestPath),const DeepCollectionEquality().hash(_avoidedCells),explanationCard);

@override
String toString() {
  return 'RouteResult(shortestPath: $shortestPath, safestPath: $safestPath, avoidedCells: $avoidedCells, explanationCard: $explanationCard)';
}


}

/// @nodoc
abstract mixin class _$RouteResultCopyWith<$Res> implements $RouteResultCopyWith<$Res> {
  factory _$RouteResultCopyWith(_RouteResult value, $Res Function(_RouteResult) _then) = __$RouteResultCopyWithImpl;
@override @useResult
$Res call({
 List<LatLng> shortestPath, List<LatLng> safestPath, List<String> avoidedCells, RouteExplanation explanationCard
});


@override $RouteExplanationCopyWith<$Res> get explanationCard;

}
/// @nodoc
class __$RouteResultCopyWithImpl<$Res>
    implements _$RouteResultCopyWith<$Res> {
  __$RouteResultCopyWithImpl(this._self, this._then);

  final _RouteResult _self;
  final $Res Function(_RouteResult) _then;

/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shortestPath = null,Object? safestPath = null,Object? avoidedCells = null,Object? explanationCard = null,}) {
  return _then(_RouteResult(
shortestPath: null == shortestPath ? _self._shortestPath : shortestPath // ignore: cast_nullable_to_non_nullable
as List<LatLng>,safestPath: null == safestPath ? _self._safestPath : safestPath // ignore: cast_nullable_to_non_nullable
as List<LatLng>,avoidedCells: null == avoidedCells ? _self._avoidedCells : avoidedCells // ignore: cast_nullable_to_non_nullable
as List<String>,explanationCard: null == explanationCard ? _self.explanationCard : explanationCard // ignore: cast_nullable_to_non_nullable
as RouteExplanation,
  ));
}

/// Create a copy of RouteResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RouteExplanationCopyWith<$Res> get explanationCard {
  
  return $RouteExplanationCopyWith<$Res>(_self.explanationCard, (value) {
    return _then(_self.copyWith(explanationCard: value));
  });
}
}

/// @nodoc
mixin _$RouteExplanation {

 Map<String, String> get avoidedCellSummaries; double get nightMultiplier; double get surgeMultiplier; double get distanceDeltaMeters; int get timeDeltaSeconds; String? get gemmaSummary;
/// Create a copy of RouteExplanation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RouteExplanationCopyWith<RouteExplanation> get copyWith => _$RouteExplanationCopyWithImpl<RouteExplanation>(this as RouteExplanation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RouteExplanation&&const DeepCollectionEquality().equals(other.avoidedCellSummaries, avoidedCellSummaries)&&(identical(other.nightMultiplier, nightMultiplier) || other.nightMultiplier == nightMultiplier)&&(identical(other.surgeMultiplier, surgeMultiplier) || other.surgeMultiplier == surgeMultiplier)&&(identical(other.distanceDeltaMeters, distanceDeltaMeters) || other.distanceDeltaMeters == distanceDeltaMeters)&&(identical(other.timeDeltaSeconds, timeDeltaSeconds) || other.timeDeltaSeconds == timeDeltaSeconds)&&(identical(other.gemmaSummary, gemmaSummary) || other.gemmaSummary == gemmaSummary));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(avoidedCellSummaries),nightMultiplier,surgeMultiplier,distanceDeltaMeters,timeDeltaSeconds,gemmaSummary);

@override
String toString() {
  return 'RouteExplanation(avoidedCellSummaries: $avoidedCellSummaries, nightMultiplier: $nightMultiplier, surgeMultiplier: $surgeMultiplier, distanceDeltaMeters: $distanceDeltaMeters, timeDeltaSeconds: $timeDeltaSeconds, gemmaSummary: $gemmaSummary)';
}


}

/// @nodoc
abstract mixin class $RouteExplanationCopyWith<$Res>  {
  factory $RouteExplanationCopyWith(RouteExplanation value, $Res Function(RouteExplanation) _then) = _$RouteExplanationCopyWithImpl;
@useResult
$Res call({
 Map<String, String> avoidedCellSummaries, double nightMultiplier, double surgeMultiplier, double distanceDeltaMeters, int timeDeltaSeconds, String? gemmaSummary
});




}
/// @nodoc
class _$RouteExplanationCopyWithImpl<$Res>
    implements $RouteExplanationCopyWith<$Res> {
  _$RouteExplanationCopyWithImpl(this._self, this._then);

  final RouteExplanation _self;
  final $Res Function(RouteExplanation) _then;

/// Create a copy of RouteExplanation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? avoidedCellSummaries = null,Object? nightMultiplier = null,Object? surgeMultiplier = null,Object? distanceDeltaMeters = null,Object? timeDeltaSeconds = null,Object? gemmaSummary = freezed,}) {
  return _then(_self.copyWith(
avoidedCellSummaries: null == avoidedCellSummaries ? _self.avoidedCellSummaries : avoidedCellSummaries // ignore: cast_nullable_to_non_nullable
as Map<String, String>,nightMultiplier: null == nightMultiplier ? _self.nightMultiplier : nightMultiplier // ignore: cast_nullable_to_non_nullable
as double,surgeMultiplier: null == surgeMultiplier ? _self.surgeMultiplier : surgeMultiplier // ignore: cast_nullable_to_non_nullable
as double,distanceDeltaMeters: null == distanceDeltaMeters ? _self.distanceDeltaMeters : distanceDeltaMeters // ignore: cast_nullable_to_non_nullable
as double,timeDeltaSeconds: null == timeDeltaSeconds ? _self.timeDeltaSeconds : timeDeltaSeconds // ignore: cast_nullable_to_non_nullable
as int,gemmaSummary: freezed == gemmaSummary ? _self.gemmaSummary : gemmaSummary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RouteExplanation].
extension RouteExplanationPatterns on RouteExplanation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RouteExplanation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RouteExplanation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RouteExplanation value)  $default,){
final _that = this;
switch (_that) {
case _RouteExplanation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RouteExplanation value)?  $default,){
final _that = this;
switch (_that) {
case _RouteExplanation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, String> avoidedCellSummaries,  double nightMultiplier,  double surgeMultiplier,  double distanceDeltaMeters,  int timeDeltaSeconds,  String? gemmaSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RouteExplanation() when $default != null:
return $default(_that.avoidedCellSummaries,_that.nightMultiplier,_that.surgeMultiplier,_that.distanceDeltaMeters,_that.timeDeltaSeconds,_that.gemmaSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, String> avoidedCellSummaries,  double nightMultiplier,  double surgeMultiplier,  double distanceDeltaMeters,  int timeDeltaSeconds,  String? gemmaSummary)  $default,) {final _that = this;
switch (_that) {
case _RouteExplanation():
return $default(_that.avoidedCellSummaries,_that.nightMultiplier,_that.surgeMultiplier,_that.distanceDeltaMeters,_that.timeDeltaSeconds,_that.gemmaSummary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, String> avoidedCellSummaries,  double nightMultiplier,  double surgeMultiplier,  double distanceDeltaMeters,  int timeDeltaSeconds,  String? gemmaSummary)?  $default,) {final _that = this;
switch (_that) {
case _RouteExplanation() when $default != null:
return $default(_that.avoidedCellSummaries,_that.nightMultiplier,_that.surgeMultiplier,_that.distanceDeltaMeters,_that.timeDeltaSeconds,_that.gemmaSummary);case _:
  return null;

}
}

}

/// @nodoc


class _RouteExplanation implements RouteExplanation {
  const _RouteExplanation({required final  Map<String, String> avoidedCellSummaries, required this.nightMultiplier, required this.surgeMultiplier, required this.distanceDeltaMeters, required this.timeDeltaSeconds, this.gemmaSummary}): _avoidedCellSummaries = avoidedCellSummaries;
  

 final  Map<String, String> _avoidedCellSummaries;
@override Map<String, String> get avoidedCellSummaries {
  if (_avoidedCellSummaries is EqualUnmodifiableMapView) return _avoidedCellSummaries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_avoidedCellSummaries);
}

@override final  double nightMultiplier;
@override final  double surgeMultiplier;
@override final  double distanceDeltaMeters;
@override final  int timeDeltaSeconds;
@override final  String? gemmaSummary;

/// Create a copy of RouteExplanation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RouteExplanationCopyWith<_RouteExplanation> get copyWith => __$RouteExplanationCopyWithImpl<_RouteExplanation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RouteExplanation&&const DeepCollectionEquality().equals(other._avoidedCellSummaries, _avoidedCellSummaries)&&(identical(other.nightMultiplier, nightMultiplier) || other.nightMultiplier == nightMultiplier)&&(identical(other.surgeMultiplier, surgeMultiplier) || other.surgeMultiplier == surgeMultiplier)&&(identical(other.distanceDeltaMeters, distanceDeltaMeters) || other.distanceDeltaMeters == distanceDeltaMeters)&&(identical(other.timeDeltaSeconds, timeDeltaSeconds) || other.timeDeltaSeconds == timeDeltaSeconds)&&(identical(other.gemmaSummary, gemmaSummary) || other.gemmaSummary == gemmaSummary));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_avoidedCellSummaries),nightMultiplier,surgeMultiplier,distanceDeltaMeters,timeDeltaSeconds,gemmaSummary);

@override
String toString() {
  return 'RouteExplanation(avoidedCellSummaries: $avoidedCellSummaries, nightMultiplier: $nightMultiplier, surgeMultiplier: $surgeMultiplier, distanceDeltaMeters: $distanceDeltaMeters, timeDeltaSeconds: $timeDeltaSeconds, gemmaSummary: $gemmaSummary)';
}


}

/// @nodoc
abstract mixin class _$RouteExplanationCopyWith<$Res> implements $RouteExplanationCopyWith<$Res> {
  factory _$RouteExplanationCopyWith(_RouteExplanation value, $Res Function(_RouteExplanation) _then) = __$RouteExplanationCopyWithImpl;
@override @useResult
$Res call({
 Map<String, String> avoidedCellSummaries, double nightMultiplier, double surgeMultiplier, double distanceDeltaMeters, int timeDeltaSeconds, String? gemmaSummary
});




}
/// @nodoc
class __$RouteExplanationCopyWithImpl<$Res>
    implements _$RouteExplanationCopyWith<$Res> {
  __$RouteExplanationCopyWithImpl(this._self, this._then);

  final _RouteExplanation _self;
  final $Res Function(_RouteExplanation) _then;

/// Create a copy of RouteExplanation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? avoidedCellSummaries = null,Object? nightMultiplier = null,Object? surgeMultiplier = null,Object? distanceDeltaMeters = null,Object? timeDeltaSeconds = null,Object? gemmaSummary = freezed,}) {
  return _then(_RouteExplanation(
avoidedCellSummaries: null == avoidedCellSummaries ? _self._avoidedCellSummaries : avoidedCellSummaries // ignore: cast_nullable_to_non_nullable
as Map<String, String>,nightMultiplier: null == nightMultiplier ? _self.nightMultiplier : nightMultiplier // ignore: cast_nullable_to_non_nullable
as double,surgeMultiplier: null == surgeMultiplier ? _self.surgeMultiplier : surgeMultiplier // ignore: cast_nullable_to_non_nullable
as double,distanceDeltaMeters: null == distanceDeltaMeters ? _self.distanceDeltaMeters : distanceDeltaMeters // ignore: cast_nullable_to_non_nullable
as double,timeDeltaSeconds: null == timeDeltaSeconds ? _self.timeDeltaSeconds : timeDeltaSeconds // ignore: cast_nullable_to_non_nullable
as int,gemmaSummary: freezed == gemmaSummary ? _self.gemmaSummary : gemmaSummary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
