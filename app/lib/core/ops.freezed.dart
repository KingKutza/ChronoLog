// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ops.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Op {

 String get op; String get map; String get id; Object? get value;
/// Create a copy of Op
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpCopyWith<Op> get copyWith => _$OpCopyWithImpl<Op>(this as Op, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Op&&(identical(other.op, op) || other.op == op)&&(identical(other.map, map) || other.map == map)&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,op,map,id,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'Op(op: $op, map: $map, id: $id, value: $value)';
}


}

/// @nodoc
abstract mixin class $OpCopyWith<$Res>  {
  factory $OpCopyWith(Op value, $Res Function(Op) _then) = _$OpCopyWithImpl;
@useResult
$Res call({
 String op, String map, String id, Object? value
});




}
/// @nodoc
class _$OpCopyWithImpl<$Res>
    implements $OpCopyWith<$Res> {
  _$OpCopyWithImpl(this._self, this._then);

  final Op _self;
  final $Res Function(Op) _then;

/// Create a copy of Op
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? op = null,Object? map = null,Object? id = null,Object? value = freezed,}) {
  return _then(Op(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,map: null == map ? _self.map : map // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value ,
  ));
}

}


/// Adds pattern-matching-related methods to [Op].
extension OpPatterns on Op {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Op value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Op() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Op value)  $default,){
final _that = this;
switch (_that) {
case _Op():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Op value)?  $default,){
final _that = this;
switch (_that) {
case _Op() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String op,  String map,  String id,  Object? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Op() when $default != null:
return $default(_that.op,_that.map,_that.id,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String op,  String map,  String id,  Object? value)  $default,) {final _that = this;
switch (_that) {
case _Op():
return $default(_that.op,_that.map,_that.id,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String op,  String map,  String id,  Object? value)?  $default,) {final _that = this;
switch (_that) {
case _Op() when $default != null:
return $default(_that.op,_that.map,_that.id,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _Op extends Op {
  const _Op({required this.op, required this.map, required this.id, this.value}): super._();
  

@override final  String op;
@override final  String map;
@override final  String id;
@override final  Object? value;

/// Create a copy of Op
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpCopyWith<_Op> get copyWith => __$OpCopyWithImpl<_Op>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Op&&(identical(other.op, op) || other.op == op)&&(identical(other.map, map) || other.map == map)&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,op,map,id,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'Op(op: $op, map: $map, id: $id, value: $value)';
}


}

/// @nodoc
abstract mixin class _$OpCopyWith<$Res> implements $OpCopyWith<$Res> {
  factory _$OpCopyWith(_Op value, $Res Function(_Op) _then) = __$OpCopyWithImpl;
@override @useResult
$Res call({
 String op, String map, String id, Object? value
});




}
/// @nodoc
class __$OpCopyWithImpl<$Res>
    implements _$OpCopyWith<$Res> {
  __$OpCopyWithImpl(this._self, this._then);

  final _Op _self;
  final $Res Function(_Op) _then;

/// Create a copy of Op
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? op = null,Object? map = null,Object? id = null,Object? value = freezed,}) {
  return _then(_Op(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,map: null == map ? _self.map : map // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,value: freezed == value ? _self.value : value ,
  ));
}


}

// dart format on
