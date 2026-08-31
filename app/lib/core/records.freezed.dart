// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'records.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Magnitude {

 String? get frame; Json? get value;
/// Create a copy of Magnitude
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<Magnitude> get copyWith => _$MagnitudeCopyWithImpl<Magnitude>(this as Magnitude, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Magnitude&&(identical(other.frame, frame) || other.frame == frame)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,frame,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'Magnitude(frame: $frame, value: $value)';
}


}

/// @nodoc
abstract mixin class $MagnitudeCopyWith<$Res>  {
  factory $MagnitudeCopyWith(Magnitude value, $Res Function(Magnitude) _then) = _$MagnitudeCopyWithImpl;
@useResult
$Res call({
 String? frame, Json? value
});




}
/// @nodoc
class _$MagnitudeCopyWithImpl<$Res>
    implements $MagnitudeCopyWith<$Res> {
  _$MagnitudeCopyWithImpl(this._self, this._then);

  final Magnitude _self;
  final $Res Function(Magnitude) _then;

/// Create a copy of Magnitude
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? frame = freezed,Object? value = freezed,}) {
  return _then(Magnitude(
frame: freezed == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as Json?,
  ));
}

}


/// Adds pattern-matching-related methods to [Magnitude].
extension MagnitudePatterns on Magnitude {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Magnitude value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Magnitude() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Magnitude value)  $default,){
final _that = this;
switch (_that) {
case _Magnitude():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Magnitude value)?  $default,){
final _that = this;
switch (_that) {
case _Magnitude() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? frame,  Json? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Magnitude() when $default != null:
return $default(_that.frame,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? frame,  Json? value)  $default,) {final _that = this;
switch (_that) {
case _Magnitude():
return $default(_that.frame,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? frame,  Json? value)?  $default,) {final _that = this;
switch (_that) {
case _Magnitude() when $default != null:
return $default(_that.frame,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _Magnitude extends Magnitude {
  const _Magnitude({this.frame,  Json? value}): _value = value,super._();
  

@override final  String? frame;
 final  Json? _value;
@override Json? get value {
  final value = _value;
  if (value == null) return null;
  if (_value is EqualUnmodifiableMapView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of Magnitude
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MagnitudeCopyWith<_Magnitude> get copyWith => __$MagnitudeCopyWithImpl<_Magnitude>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Magnitude&&(identical(other.frame, frame) || other.frame == frame)&&const DeepCollectionEquality().equals(other._value, _value));
}


@override
int get hashCode => Object.hash(runtimeType,frame,const DeepCollectionEquality().hash(_value));

@override
String toString() {
  return 'Magnitude(frame: $frame, value: $value)';
}


}

/// @nodoc
abstract mixin class _$MagnitudeCopyWith<$Res> implements $MagnitudeCopyWith<$Res> {
  factory _$MagnitudeCopyWith(_Magnitude value, $Res Function(_Magnitude) _then) = __$MagnitudeCopyWithImpl;
@override @useResult
$Res call({
 String? frame, Json? value
});




}
/// @nodoc
class __$MagnitudeCopyWithImpl<$Res>
    implements _$MagnitudeCopyWith<$Res> {
  __$MagnitudeCopyWithImpl(this._self, this._then);

  final _Magnitude _self;
  final $Res Function(_Magnitude) _then;

/// Create a copy of Magnitude
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? frame = freezed,Object? value = freezed,}) {
  return _then(_Magnitude(
frame: freezed == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as Json?,
  ));
}


}

/// @nodoc
mixin _$Spread {

 Magnitude? get before; Magnitude? get after;
/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SpreadCopyWith<Spread> get copyWith => _$SpreadCopyWithImpl<Spread>(this as Spread, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Spread&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}


@override
int get hashCode => Object.hash(runtimeType,before,after);

@override
String toString() {
  return 'Spread(before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class $SpreadCopyWith<$Res>  {
  factory $SpreadCopyWith(Spread value, $Res Function(Spread) _then) = _$SpreadCopyWithImpl;
@useResult
$Res call({
 Magnitude? before, Magnitude? after
});


$MagnitudeCopyWith<$Res>? get before;$MagnitudeCopyWith<$Res>? get after;

}
/// @nodoc
class _$SpreadCopyWithImpl<$Res>
    implements $SpreadCopyWith<$Res> {
  _$SpreadCopyWithImpl(this._self, this._then);

  final Spread _self;
  final $Res Function(Spread) _then;

/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? before = freezed,Object? after = freezed,}) {
  return _then(Spread(
before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as Magnitude?,after: freezed == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as Magnitude?,
  ));
}
/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<$Res>? get before {
    if (_self.before == null) {
    return null;
  }

  return $MagnitudeCopyWith<$Res>(_self.before!, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<$Res>? get after {
    if (_self.after == null) {
    return null;
  }

  return $MagnitudeCopyWith<$Res>(_self.after!, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}


/// Adds pattern-matching-related methods to [Spread].
extension SpreadPatterns on Spread {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Spread value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Spread() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Spread value)  $default,){
final _that = this;
switch (_that) {
case _Spread():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Spread value)?  $default,){
final _that = this;
switch (_that) {
case _Spread() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Magnitude? before,  Magnitude? after)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Spread() when $default != null:
return $default(_that.before,_that.after);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Magnitude? before,  Magnitude? after)  $default,) {final _that = this;
switch (_that) {
case _Spread():
return $default(_that.before,_that.after);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Magnitude? before,  Magnitude? after)?  $default,) {final _that = this;
switch (_that) {
case _Spread() when $default != null:
return $default(_that.before,_that.after);case _:
  return null;

}
}

}

/// @nodoc


class _Spread extends Spread {
  const _Spread({this.before, this.after}): super._();
  

@override final  Magnitude? before;
@override final  Magnitude? after;

/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SpreadCopyWith<_Spread> get copyWith => __$SpreadCopyWithImpl<_Spread>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Spread&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}


@override
int get hashCode => Object.hash(runtimeType,before,after);

@override
String toString() {
  return 'Spread(before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class _$SpreadCopyWith<$Res> implements $SpreadCopyWith<$Res> {
  factory _$SpreadCopyWith(_Spread value, $Res Function(_Spread) _then) = __$SpreadCopyWithImpl;
@override @useResult
$Res call({
 Magnitude? before, Magnitude? after
});


@override $MagnitudeCopyWith<$Res>? get before;@override $MagnitudeCopyWith<$Res>? get after;

}
/// @nodoc
class __$SpreadCopyWithImpl<$Res>
    implements _$SpreadCopyWith<$Res> {
  __$SpreadCopyWithImpl(this._self, this._then);

  final _Spread _self;
  final $Res Function(_Spread) _then;

/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? before = freezed,Object? after = freezed,}) {
  return _then(_Spread(
before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as Magnitude?,after: freezed == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as Magnitude?,
  ));
}

/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<$Res>? get before {
    if (_self.before == null) {
    return null;
  }

  return $MagnitudeCopyWith<$Res>(_self.before!, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of Spread
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<$Res>? get after {
    if (_self.after == null) {
    return null;
  }

  return $MagnitudeCopyWith<$Res>(_self.after!, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}

/// @nodoc
mixin _$Frame {

 String get id; String? get title; List<String> get traits; Json get extra;
/// Create a copy of Frame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrameCopyWith<Frame> get copyWith => _$FrameCopyWithImpl<Frame>(this as Frame, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Frame&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.traits, traits)&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(traits),const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'Frame(id: $id, title: $title, traits: $traits, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $FrameCopyWith<$Res>  {
  factory $FrameCopyWith(Frame value, $Res Function(Frame) _then) = _$FrameCopyWithImpl;
@useResult
$Res call({
 String id, String? title, List<String> traits, Json extra
});




}
/// @nodoc
class _$FrameCopyWithImpl<$Res>
    implements $FrameCopyWith<$Res> {
  _$FrameCopyWithImpl(this._self, this._then);

  final Frame _self;
  final $Res Function(Frame) _then;

/// Create a copy of Frame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = freezed,Object? traits = null,Object? extra = null,}) {
  return _then(Frame(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,traits: null == traits ? _self.traits : traits // ignore: cast_nullable_to_non_nullable
as List<String>,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Frame].
extension FramePatterns on Frame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Frame value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Frame() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Frame value)  $default,){
final _that = this;
switch (_that) {
case _Frame():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Frame value)?  $default,){
final _that = this;
switch (_that) {
case _Frame() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? title,  List<String> traits,  Json extra)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Frame() when $default != null:
return $default(_that.id,_that.title,_that.traits,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? title,  List<String> traits,  Json extra)  $default,) {final _that = this;
switch (_that) {
case _Frame():
return $default(_that.id,_that.title,_that.traits,_that.extra);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? title,  List<String> traits,  Json extra)?  $default,) {final _that = this;
switch (_that) {
case _Frame() when $default != null:
return $default(_that.id,_that.title,_that.traits,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class _Frame extends Frame {
  const _Frame({required this.id, this.title,  List<String> traits = const <String>[],  Json extra = const <String, dynamic>{}}): _traits = traits,_extra = extra,super._();
  

@override final  String id;
@override final  String? title;
 final  List<String> _traits;
@override@JsonKey() List<String> get traits {
  if (_traits is EqualUnmodifiableListView) return _traits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_traits);
}

 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of Frame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrameCopyWith<_Frame> get copyWith => __$FrameCopyWithImpl<_Frame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Frame&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._traits, _traits)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_traits),const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'Frame(id: $id, title: $title, traits: $traits, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$FrameCopyWith<$Res> implements $FrameCopyWith<$Res> {
  factory _$FrameCopyWith(_Frame value, $Res Function(_Frame) _then) = __$FrameCopyWithImpl;
@override @useResult
$Res call({
 String id, String? title, List<String> traits, Json extra
});




}
/// @nodoc
class __$FrameCopyWithImpl<$Res>
    implements _$FrameCopyWith<$Res> {
  __$FrameCopyWithImpl(this._self, this._then);

  final _Frame _self;
  final $Res Function(_Frame) _then;

/// Create a copy of Frame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = freezed,Object? traits = null,Object? extra = null,}) {
  return _then(_Frame(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,traits: null == traits ? _self._traits : traits // ignore: cast_nullable_to_non_nullable
as List<String>,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$Event {

 String get id; List<String> get traits; Map<String, Magnitude> get magnitudes; Json? get payload; Json get extra;
/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventCopyWith<Event> get copyWith => _$EventCopyWithImpl<Event>(this as Event, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Event&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.traits, traits)&&const DeepCollectionEquality().equals(other.magnitudes, magnitudes)&&const DeepCollectionEquality().equals(other.payload, payload)&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(traits),const DeepCollectionEquality().hash(magnitudes),const DeepCollectionEquality().hash(payload),const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'Event(id: $id, traits: $traits, magnitudes: $magnitudes, payload: $payload, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $EventCopyWith<$Res>  {
  factory $EventCopyWith(Event value, $Res Function(Event) _then) = _$EventCopyWithImpl;
@useResult
$Res call({
 String id, List<String> traits, Map<String, Magnitude> magnitudes, Json? payload, Json extra
});




}
/// @nodoc
class _$EventCopyWithImpl<$Res>
    implements $EventCopyWith<$Res> {
  _$EventCopyWithImpl(this._self, this._then);

  final Event _self;
  final $Res Function(Event) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? traits = null,Object? magnitudes = null,Object? payload = freezed,Object? extra = null,}) {
  return _then(Event(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,traits: null == traits ? _self.traits : traits // ignore: cast_nullable_to_non_nullable
as List<String>,magnitudes: null == magnitudes ? _self.magnitudes : magnitudes // ignore: cast_nullable_to_non_nullable
as Map<String, Magnitude>,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Json?,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Event].
extension EventPatterns on Event {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Event value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Event() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Event value)  $default,){
final _that = this;
switch (_that) {
case _Event():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Event value)?  $default,){
final _that = this;
switch (_that) {
case _Event() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  List<String> traits,  Map<String, Magnitude> magnitudes,  Json? payload,  Json extra)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Event() when $default != null:
return $default(_that.id,_that.traits,_that.magnitudes,_that.payload,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  List<String> traits,  Map<String, Magnitude> magnitudes,  Json? payload,  Json extra)  $default,) {final _that = this;
switch (_that) {
case _Event():
return $default(_that.id,_that.traits,_that.magnitudes,_that.payload,_that.extra);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  List<String> traits,  Map<String, Magnitude> magnitudes,  Json? payload,  Json extra)?  $default,) {final _that = this;
switch (_that) {
case _Event() when $default != null:
return $default(_that.id,_that.traits,_that.magnitudes,_that.payload,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class _Event extends Event {
  const _Event({required this.id,  List<String> traits = const <String>[],  Map<String, Magnitude> magnitudes = const <String, Magnitude>{},  Json? payload,  Json extra = const <String, dynamic>{}}): _traits = traits,_magnitudes = magnitudes,_payload = payload,_extra = extra,super._();
  

@override final  String id;
 final  List<String> _traits;
@override@JsonKey() List<String> get traits {
  if (_traits is EqualUnmodifiableListView) return _traits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_traits);
}

 final  Map<String, Magnitude> _magnitudes;
@override@JsonKey() Map<String, Magnitude> get magnitudes {
  if (_magnitudes is EqualUnmodifiableMapView) return _magnitudes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_magnitudes);
}

 final  Json? _payload;
@override Json? get payload {
  final value = _payload;
  if (value == null) return null;
  if (_payload is EqualUnmodifiableMapView) return _payload;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EventCopyWith<_Event> get copyWith => __$EventCopyWithImpl<_Event>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Event&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other._traits, _traits)&&const DeepCollectionEquality().equals(other._magnitudes, _magnitudes)&&const DeepCollectionEquality().equals(other._payload, _payload)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_traits),const DeepCollectionEquality().hash(_magnitudes),const DeepCollectionEquality().hash(_payload),const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'Event(id: $id, traits: $traits, magnitudes: $magnitudes, payload: $payload, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$EventCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory _$EventCopyWith(_Event value, $Res Function(_Event) _then) = __$EventCopyWithImpl;
@override @useResult
$Res call({
 String id, List<String> traits, Map<String, Magnitude> magnitudes, Json? payload, Json extra
});




}
/// @nodoc
class __$EventCopyWithImpl<$Res>
    implements _$EventCopyWith<$Res> {
  __$EventCopyWithImpl(this._self, this._then);

  final _Event _self;
  final $Res Function(_Event) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? traits = null,Object? magnitudes = null,Object? payload = freezed,Object? extra = null,}) {
  return _then(_Event(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,traits: null == traits ? _self._traits : traits // ignore: cast_nullable_to_non_nullable
as List<String>,magnitudes: null == magnitudes ? _self._magnitudes : magnitudes // ignore: cast_nullable_to_non_nullable
as Map<String, Magnitude>,payload: freezed == payload ? _self._payload : payload // ignore: cast_nullable_to_non_nullable
as Json?,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$Pattern {

 String get id; String? get language; Json get extra;
/// Create a copy of Pattern
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PatternCopyWith<Pattern> get copyWith => _$PatternCopyWithImpl<Pattern>(this as Pattern, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Pattern&&(identical(other.id, id) || other.id == id)&&(identical(other.language, language) || other.language == language)&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,language,const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'Pattern(id: $id, language: $language, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $PatternCopyWith<$Res>  {
  factory $PatternCopyWith(Pattern value, $Res Function(Pattern) _then) = _$PatternCopyWithImpl;
@useResult
$Res call({
 String id, String? language, Json extra
});




}
/// @nodoc
class _$PatternCopyWithImpl<$Res>
    implements $PatternCopyWith<$Res> {
  _$PatternCopyWithImpl(this._self, this._then);

  final Pattern _self;
  final $Res Function(Pattern) _then;

/// Create a copy of Pattern
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? language = freezed,Object? extra = null,}) {
  return _then(Pattern(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Pattern].
extension PatternPatterns on Pattern {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Pattern value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Pattern() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Pattern value)  $default,){
final _that = this;
switch (_that) {
case _Pattern():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Pattern value)?  $default,){
final _that = this;
switch (_that) {
case _Pattern() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? language,  Json extra)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Pattern() when $default != null:
return $default(_that.id,_that.language,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? language,  Json extra)  $default,) {final _that = this;
switch (_that) {
case _Pattern():
return $default(_that.id,_that.language,_that.extra);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? language,  Json extra)?  $default,) {final _that = this;
switch (_that) {
case _Pattern() when $default != null:
return $default(_that.id,_that.language,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class _Pattern extends Pattern {
  const _Pattern({required this.id, this.language,  Json extra = const <String, dynamic>{}}): _extra = extra,super._();
  

@override final  String id;
@override final  String? language;
 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of Pattern
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PatternCopyWith<_Pattern> get copyWith => __$PatternCopyWithImpl<_Pattern>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Pattern&&(identical(other.id, id) || other.id == id)&&(identical(other.language, language) || other.language == language)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,language,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'Pattern(id: $id, language: $language, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$PatternCopyWith<$Res> implements $PatternCopyWith<$Res> {
  factory _$PatternCopyWith(_Pattern value, $Res Function(_Pattern) _then) = __$PatternCopyWithImpl;
@override @useResult
$Res call({
 String id, String? language, Json extra
});




}
/// @nodoc
class __$PatternCopyWithImpl<$Res>
    implements _$PatternCopyWith<$Res> {
  __$PatternCopyWithImpl(this._self, this._then);

  final _Pattern _self;
  final $Res Function(_Pattern) _then;

/// Create a copy of Pattern
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? language = freezed,Object? extra = null,}) {
  return _then(_Pattern(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$Override {

 String get id; String get virtualId; bool get suppress; List<String> get replacements; Json get extra;
/// Create a copy of Override
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OverrideCopyWith<Override> get copyWith => _$OverrideCopyWithImpl<Override>(this as Override, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Override&&(identical(other.id, id) || other.id == id)&&(identical(other.virtualId, virtualId) || other.virtualId == virtualId)&&(identical(other.suppress, suppress) || other.suppress == suppress)&&const DeepCollectionEquality().equals(other.replacements, replacements)&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,virtualId,suppress,const DeepCollectionEquality().hash(replacements),const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'Override(id: $id, virtualId: $virtualId, suppress: $suppress, replacements: $replacements, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $OverrideCopyWith<$Res>  {
  factory $OverrideCopyWith(Override value, $Res Function(Override) _then) = _$OverrideCopyWithImpl;
@useResult
$Res call({
 String id, String virtualId, bool suppress, List<String> replacements, Json extra
});




}
/// @nodoc
class _$OverrideCopyWithImpl<$Res>
    implements $OverrideCopyWith<$Res> {
  _$OverrideCopyWithImpl(this._self, this._then);

  final Override _self;
  final $Res Function(Override) _then;

/// Create a copy of Override
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? virtualId = null,Object? suppress = null,Object? replacements = null,Object? extra = null,}) {
  return _then(Override(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,virtualId: null == virtualId ? _self.virtualId : virtualId // ignore: cast_nullable_to_non_nullable
as String,suppress: null == suppress ? _self.suppress : suppress // ignore: cast_nullable_to_non_nullable
as bool,replacements: null == replacements ? _self.replacements : replacements // ignore: cast_nullable_to_non_nullable
as List<String>,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Override].
extension OverridePatterns on Override {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Override value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Override() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Override value)  $default,){
final _that = this;
switch (_that) {
case _Override():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Override value)?  $default,){
final _that = this;
switch (_that) {
case _Override() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String virtualId,  bool suppress,  List<String> replacements,  Json extra)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Override() when $default != null:
return $default(_that.id,_that.virtualId,_that.suppress,_that.replacements,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String virtualId,  bool suppress,  List<String> replacements,  Json extra)  $default,) {final _that = this;
switch (_that) {
case _Override():
return $default(_that.id,_that.virtualId,_that.suppress,_that.replacements,_that.extra);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String virtualId,  bool suppress,  List<String> replacements,  Json extra)?  $default,) {final _that = this;
switch (_that) {
case _Override() when $default != null:
return $default(_that.id,_that.virtualId,_that.suppress,_that.replacements,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class _Override extends Override {
  const _Override({required this.id, this.virtualId = '', this.suppress = false,  List<String> replacements = const <String>[],  Json extra = const <String, dynamic>{}}): _replacements = replacements,_extra = extra,super._();
  

@override final  String id;
@override@JsonKey() final  String virtualId;
@override@JsonKey() final  bool suppress;
 final  List<String> _replacements;
@override@JsonKey() List<String> get replacements {
  if (_replacements is EqualUnmodifiableListView) return _replacements;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_replacements);
}

 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of Override
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OverrideCopyWith<_Override> get copyWith => __$OverrideCopyWithImpl<_Override>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Override&&(identical(other.id, id) || other.id == id)&&(identical(other.virtualId, virtualId) || other.virtualId == virtualId)&&(identical(other.suppress, suppress) || other.suppress == suppress)&&const DeepCollectionEquality().equals(other._replacements, _replacements)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,virtualId,suppress,const DeepCollectionEquality().hash(_replacements),const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'Override(id: $id, virtualId: $virtualId, suppress: $suppress, replacements: $replacements, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$OverrideCopyWith<$Res> implements $OverrideCopyWith<$Res> {
  factory _$OverrideCopyWith(_Override value, $Res Function(_Override) _then) = __$OverrideCopyWithImpl;
@override @useResult
$Res call({
 String id, String virtualId, bool suppress, List<String> replacements, Json extra
});




}
/// @nodoc
class __$OverrideCopyWithImpl<$Res>
    implements _$OverrideCopyWith<$Res> {
  __$OverrideCopyWithImpl(this._self, this._then);

  final _Override _self;
  final $Res Function(_Override) _then;

/// Create a copy of Override
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? virtualId = null,Object? suppress = null,Object? replacements = null,Object? extra = null,}) {
  return _then(_Override(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,virtualId: null == virtualId ? _self.virtualId : virtualId // ignore: cast_nullable_to_non_nullable
as String,suppress: null == suppress ? _self.suppress : suppress // ignore: cast_nullable_to_non_nullable
as bool,replacements: null == replacements ? _self._replacements : replacements // ignore: cast_nullable_to_non_nullable
as List<String>,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$Relation {

 String get id; String get type; Json get extra;
/// Create a copy of Relation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RelationCopyWith<Relation> get copyWith => _$RelationCopyWithImpl<Relation>(this as Relation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Relation&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'Relation(id: $id, type: $type, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $RelationCopyWith<$Res>  {
  factory $RelationCopyWith(Relation value, $Res Function(Relation) _then) = _$RelationCopyWithImpl;
@useResult
$Res call({
 String id, String type, Json extra
});




}
/// @nodoc
class _$RelationCopyWithImpl<$Res>
    implements $RelationCopyWith<$Res> {
  _$RelationCopyWithImpl(this._self, this._then);

  final Relation _self;
  final $Res Function(Relation) _then;

/// Create a copy of Relation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? extra = null,}) {
  return _then(Relation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Relation].
extension RelationPatterns on Relation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Relation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Relation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Relation value)  $default,){
final _that = this;
switch (_that) {
case _Relation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Relation value)?  $default,){
final _that = this;
switch (_that) {
case _Relation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String type,  Json extra)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Relation() when $default != null:
return $default(_that.id,_that.type,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String type,  Json extra)  $default,) {final _that = this;
switch (_that) {
case _Relation():
return $default(_that.id,_that.type,_that.extra);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String type,  Json extra)?  $default,) {final _that = this;
switch (_that) {
case _Relation() when $default != null:
return $default(_that.id,_that.type,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class _Relation extends Relation {
  const _Relation({required this.id, required this.type,  Json extra = const <String, dynamic>{}}): _extra = extra,super._();
  

@override final  String id;
@override final  String type;
 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of Relation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RelationCopyWith<_Relation> get copyWith => __$RelationCopyWithImpl<_Relation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Relation&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'Relation(id: $id, type: $type, extra: $extra)';
}


}

/// @nodoc
abstract mixin class _$RelationCopyWith<$Res> implements $RelationCopyWith<$Res> {
  factory _$RelationCopyWith(_Relation value, $Res Function(_Relation) _then) = __$RelationCopyWithImpl;
@override @useResult
$Res call({
 String id, String type, Json extra
});




}
/// @nodoc
class __$RelationCopyWithImpl<$Res>
    implements _$RelationCopyWith<$Res> {
  __$RelationCopyWithImpl(this._self, this._then);

  final _Relation _self;
  final $Res Function(_Relation) _then;

/// Create a copy of Relation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? extra = null,}) {
  return _then(_Relation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$StapleEnd {

 Json get extra;
/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StapleEndCopyWith<StapleEnd> get copyWith => _$StapleEndCopyWithImpl<StapleEnd>(this as StapleEnd, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StapleEnd&&const DeepCollectionEquality().equals(other.extra, extra));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(extra));

@override
String toString() {
  return 'StapleEnd(extra: $extra)';
}


}

/// @nodoc
abstract mixin class $StapleEndCopyWith<$Res>  {
  factory $StapleEndCopyWith(StapleEnd value, $Res Function(StapleEnd) _then) = _$StapleEndCopyWithImpl;
@useResult
$Res call({
 Json extra
});




}
/// @nodoc
class _$StapleEndCopyWithImpl<$Res>
    implements $StapleEndCopyWith<$Res> {
  _$StapleEndCopyWithImpl(this._self, this._then);

  final StapleEnd _self;
  final $Res Function(StapleEnd) _then;

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? extra = null,}) {
  return _then(_self.copyWith(
extra: null == extra ? _self.extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [StapleEnd].
extension StapleEndPatterns on StapleEnd {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FrameEnd value)?  frame,TResult Function( ObjectEnd value)?  object,TResult Function( SeriesEnd value)?  series,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FrameEnd() when frame != null:
return frame(_that);case ObjectEnd() when object != null:
return object(_that);case SeriesEnd() when series != null:
return series(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FrameEnd value)  frame,required TResult Function( ObjectEnd value)  object,required TResult Function( SeriesEnd value)  series,}){
final _that = this;
switch (_that) {
case FrameEnd():
return frame(_that);case ObjectEnd():
return object(_that);case SeriesEnd():
return series(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FrameEnd value)?  frame,TResult? Function( ObjectEnd value)?  object,TResult? Function( SeriesEnd value)?  series,}){
final _that = this;
switch (_that) {
case FrameEnd() when frame != null:
return frame(_that);case ObjectEnd() when object != null:
return object(_that);case SeriesEnd() when series != null:
return series(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String frame,  Position? position,  Json extra)?  frame,TResult Function( String object,  String? point,  Magnitude? offset,  Json extra)?  object,TResult Function( String series,  Json extra)?  series,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FrameEnd() when frame != null:
return frame(_that.frame,_that.position,_that.extra);case ObjectEnd() when object != null:
return object(_that.object,_that.point,_that.offset,_that.extra);case SeriesEnd() when series != null:
return series(_that.series,_that.extra);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String frame,  Position? position,  Json extra)  frame,required TResult Function( String object,  String? point,  Magnitude? offset,  Json extra)  object,required TResult Function( String series,  Json extra)  series,}) {final _that = this;
switch (_that) {
case FrameEnd():
return frame(_that.frame,_that.position,_that.extra);case ObjectEnd():
return object(_that.object,_that.point,_that.offset,_that.extra);case SeriesEnd():
return series(_that.series,_that.extra);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String frame,  Position? position,  Json extra)?  frame,TResult? Function( String object,  String? point,  Magnitude? offset,  Json extra)?  object,TResult? Function( String series,  Json extra)?  series,}) {final _that = this;
switch (_that) {
case FrameEnd() when frame != null:
return frame(_that.frame,_that.position,_that.extra);case ObjectEnd() when object != null:
return object(_that.object,_that.point,_that.offset,_that.extra);case SeriesEnd() when series != null:
return series(_that.series,_that.extra);case _:
  return null;

}
}

}

/// @nodoc


class FrameEnd extends StapleEnd {
  const FrameEnd(this.frame, {this.position,  Json extra = const <String, dynamic>{}}): _extra = extra,super._();
  

 final  String frame;
 final  Position? position;
 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrameEndCopyWith<FrameEnd> get copyWith => _$FrameEndCopyWithImpl<FrameEnd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrameEnd&&(identical(other.frame, frame) || other.frame == frame)&&(identical(other.position, position) || other.position == position)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,frame,position,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'StapleEnd.frame(frame: $frame, position: $position, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $FrameEndCopyWith<$Res> implements $StapleEndCopyWith<$Res> {
  factory $FrameEndCopyWith(FrameEnd value, $Res Function(FrameEnd) _then) = _$FrameEndCopyWithImpl;
@override @useResult
$Res call({
 String frame, Position? position, Json extra
});


$PositionCopyWith<$Res>? get position;

}
/// @nodoc
class _$FrameEndCopyWithImpl<$Res>
    implements $FrameEndCopyWith<$Res> {
  _$FrameEndCopyWithImpl(this._self, this._then);

  final FrameEnd _self;
  final $Res Function(FrameEnd) _then;

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? frame = null,Object? position = freezed,Object? extra = null,}) {
  return _then(FrameEnd(
null == frame ? _self.frame : frame // ignore: cast_nullable_to_non_nullable
as String,position: freezed == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Position?,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PositionCopyWith<$Res>? get position {
    if (_self.position == null) {
    return null;
  }

  return $PositionCopyWith<$Res>(_self.position!, (value) {
    return _then(_self.copyWith(position: value));
  });
}
}

/// @nodoc


class ObjectEnd extends StapleEnd {
  const ObjectEnd(this.object, {this.point, this.offset,  Json extra = const <String, dynamic>{}}): _extra = extra,super._();
  

 final  String object;
 final  String? point;
 final  Magnitude? offset;
 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObjectEndCopyWith<ObjectEnd> get copyWith => _$ObjectEndCopyWithImpl<ObjectEnd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObjectEnd&&(identical(other.object, object) || other.object == object)&&(identical(other.point, point) || other.point == point)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,object,point,offset,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'StapleEnd.object(object: $object, point: $point, offset: $offset, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $ObjectEndCopyWith<$Res> implements $StapleEndCopyWith<$Res> {
  factory $ObjectEndCopyWith(ObjectEnd value, $Res Function(ObjectEnd) _then) = _$ObjectEndCopyWithImpl;
@override @useResult
$Res call({
 String object, String? point, Magnitude? offset, Json extra
});


$MagnitudeCopyWith<$Res>? get offset;

}
/// @nodoc
class _$ObjectEndCopyWithImpl<$Res>
    implements $ObjectEndCopyWith<$Res> {
  _$ObjectEndCopyWithImpl(this._self, this._then);

  final ObjectEnd _self;
  final $Res Function(ObjectEnd) _then;

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? object = null,Object? point = freezed,Object? offset = freezed,Object? extra = null,}) {
  return _then(ObjectEnd(
null == object ? _self.object : object // ignore: cast_nullable_to_non_nullable
as String,point: freezed == point ? _self.point : point // ignore: cast_nullable_to_non_nullable
as String?,offset: freezed == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as Magnitude?,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MagnitudeCopyWith<$Res>? get offset {
    if (_self.offset == null) {
    return null;
  }

  return $MagnitudeCopyWith<$Res>(_self.offset!, (value) {
    return _then(_self.copyWith(offset: value));
  });
}
}

/// @nodoc


class SeriesEnd extends StapleEnd {
  const SeriesEnd(this.series, { Json extra = const <String, dynamic>{}}): _extra = extra,super._();
  

 final  String series;
 final  Json _extra;
@override@JsonKey() Json get extra {
  if (_extra is EqualUnmodifiableMapView) return _extra;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extra);
}


/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeriesEndCopyWith<SeriesEnd> get copyWith => _$SeriesEndCopyWithImpl<SeriesEnd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeriesEnd&&(identical(other.series, series) || other.series == series)&&const DeepCollectionEquality().equals(other._extra, _extra));
}


@override
int get hashCode => Object.hash(runtimeType,series,const DeepCollectionEquality().hash(_extra));

@override
String toString() {
  return 'StapleEnd.series(series: $series, extra: $extra)';
}


}

/// @nodoc
abstract mixin class $SeriesEndCopyWith<$Res> implements $StapleEndCopyWith<$Res> {
  factory $SeriesEndCopyWith(SeriesEnd value, $Res Function(SeriesEnd) _then) = _$SeriesEndCopyWithImpl;
@override @useResult
$Res call({
 String series, Json extra
});




}
/// @nodoc
class _$SeriesEndCopyWithImpl<$Res>
    implements $SeriesEndCopyWith<$Res> {
  _$SeriesEndCopyWithImpl(this._self, this._then);

  final SeriesEnd _self;
  final $Res Function(SeriesEnd) _then;

/// Create a copy of StapleEnd
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? series = null,Object? extra = null,}) {
  return _then(SeriesEnd(
null == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as String,extra: null == extra ? _self._extra : extra // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc
mixin _$Position {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Position);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'Position()';
}


}

/// @nodoc
class $PositionCopyWith<$Res>  {
$PositionCopyWith(Position _, $Res Function(Position) __);
}


/// Adds pattern-matching-related methods to [Position].
extension PositionPatterns on Position {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoordinatePosition value)?  coordinate,TResult Function( SelectorPosition value)?  selector,TResult Function( SpanPosition value)?  span,TResult Function( VoidPosition value)?  authoredVoid,TResult Function( PointPosition value)?  point,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoordinatePosition() when coordinate != null:
return coordinate(_that);case SelectorPosition() when selector != null:
return selector(_that);case SpanPosition() when span != null:
return span(_that);case VoidPosition() when authoredVoid != null:
return authoredVoid(_that);case PointPosition() when point != null:
return point(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoordinatePosition value)  coordinate,required TResult Function( SelectorPosition value)  selector,required TResult Function( SpanPosition value)  span,required TResult Function( VoidPosition value)  authoredVoid,required TResult Function( PointPosition value)  point,}){
final _that = this;
switch (_that) {
case CoordinatePosition():
return coordinate(_that);case SelectorPosition():
return selector(_that);case SpanPosition():
return span(_that);case VoidPosition():
return authoredVoid(_that);case PointPosition():
return point(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoordinatePosition value)?  coordinate,TResult? Function( SelectorPosition value)?  selector,TResult? Function( SpanPosition value)?  span,TResult? Function( VoidPosition value)?  authoredVoid,TResult? Function( PointPosition value)?  point,}){
final _that = this;
switch (_that) {
case CoordinatePosition() when coordinate != null:
return coordinate(_that);case SelectorPosition() when selector != null:
return selector(_that);case SpanPosition() when span != null:
return span(_that);case VoidPosition() when authoredVoid != null:
return authoredVoid(_that);case PointPosition() when point != null:
return point(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Json json)?  coordinate,TResult Function( Json json)?  selector,TResult Function( Json json)?  span,TResult Function()?  authoredVoid,TResult Function( Object? source)?  point,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoordinatePosition() when coordinate != null:
return coordinate(_that.json);case SelectorPosition() when selector != null:
return selector(_that.json);case SpanPosition() when span != null:
return span(_that.json);case VoidPosition() when authoredVoid != null:
return authoredVoid();case PointPosition() when point != null:
return point(_that.source);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Json json)  coordinate,required TResult Function( Json json)  selector,required TResult Function( Json json)  span,required TResult Function()  authoredVoid,required TResult Function( Object? source)  point,}) {final _that = this;
switch (_that) {
case CoordinatePosition():
return coordinate(_that.json);case SelectorPosition():
return selector(_that.json);case SpanPosition():
return span(_that.json);case VoidPosition():
return authoredVoid();case PointPosition():
return point(_that.source);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Json json)?  coordinate,TResult? Function( Json json)?  selector,TResult? Function( Json json)?  span,TResult? Function()?  authoredVoid,TResult? Function( Object? source)?  point,}) {final _that = this;
switch (_that) {
case CoordinatePosition() when coordinate != null:
return coordinate(_that.json);case SelectorPosition() when selector != null:
return selector(_that.json);case SpanPosition() when span != null:
return span(_that.json);case VoidPosition() when authoredVoid != null:
return authoredVoid();case PointPosition() when point != null:
return point(_that.source);case _:
  return null;

}
}

}

/// @nodoc


class CoordinatePosition extends Position {
  const CoordinatePosition( Json json): _json = json,super._();
  

 final  Json _json;
 Json get json {
  if (_json is EqualUnmodifiableMapView) return _json;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_json);
}


/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoordinatePositionCopyWith<CoordinatePosition> get copyWith => _$CoordinatePositionCopyWithImpl<CoordinatePosition>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoordinatePosition&&const DeepCollectionEquality().equals(other._json, _json));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_json));

@override
String toString() {
  return 'Position.coordinate(json: $json)';
}


}

/// @nodoc
abstract mixin class $CoordinatePositionCopyWith<$Res> implements $PositionCopyWith<$Res> {
  factory $CoordinatePositionCopyWith(CoordinatePosition value, $Res Function(CoordinatePosition) _then) = _$CoordinatePositionCopyWithImpl;
@useResult
$Res call({
 Json json
});




}
/// @nodoc
class _$CoordinatePositionCopyWithImpl<$Res>
    implements $CoordinatePositionCopyWith<$Res> {
  _$CoordinatePositionCopyWithImpl(this._self, this._then);

  final CoordinatePosition _self;
  final $Res Function(CoordinatePosition) _then;

/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(CoordinatePosition(
null == json ? _self._json : json // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc


class SelectorPosition extends Position {
  const SelectorPosition( Json json): _json = json,super._();
  

 final  Json _json;
 Json get json {
  if (_json is EqualUnmodifiableMapView) return _json;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_json);
}


/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SelectorPositionCopyWith<SelectorPosition> get copyWith => _$SelectorPositionCopyWithImpl<SelectorPosition>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SelectorPosition&&const DeepCollectionEquality().equals(other._json, _json));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_json));

@override
String toString() {
  return 'Position.selector(json: $json)';
}


}

/// @nodoc
abstract mixin class $SelectorPositionCopyWith<$Res> implements $PositionCopyWith<$Res> {
  factory $SelectorPositionCopyWith(SelectorPosition value, $Res Function(SelectorPosition) _then) = _$SelectorPositionCopyWithImpl;
@useResult
$Res call({
 Json json
});




}
/// @nodoc
class _$SelectorPositionCopyWithImpl<$Res>
    implements $SelectorPositionCopyWith<$Res> {
  _$SelectorPositionCopyWithImpl(this._self, this._then);

  final SelectorPosition _self;
  final $Res Function(SelectorPosition) _then;

/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(SelectorPosition(
null == json ? _self._json : json // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc


class SpanPosition extends Position {
  const SpanPosition( Json json): _json = json,super._();
  

 final  Json _json;
 Json get json {
  if (_json is EqualUnmodifiableMapView) return _json;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_json);
}


/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SpanPositionCopyWith<SpanPosition> get copyWith => _$SpanPositionCopyWithImpl<SpanPosition>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpanPosition&&const DeepCollectionEquality().equals(other._json, _json));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_json));

@override
String toString() {
  return 'Position.span(json: $json)';
}


}

/// @nodoc
abstract mixin class $SpanPositionCopyWith<$Res> implements $PositionCopyWith<$Res> {
  factory $SpanPositionCopyWith(SpanPosition value, $Res Function(SpanPosition) _then) = _$SpanPositionCopyWithImpl;
@useResult
$Res call({
 Json json
});




}
/// @nodoc
class _$SpanPositionCopyWithImpl<$Res>
    implements $SpanPositionCopyWith<$Res> {
  _$SpanPositionCopyWithImpl(this._self, this._then);

  final SpanPosition _self;
  final $Res Function(SpanPosition) _then;

/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(SpanPosition(
null == json ? _self._json : json // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

/// @nodoc


class VoidPosition extends Position {
  const VoidPosition(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VoidPosition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'Position.authoredVoid()';
}


}




/// @nodoc


class PointPosition extends Position {
  const PointPosition(this.source): super._();
  

 final  Object? source;

/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PointPositionCopyWith<PointPosition> get copyWith => _$PointPositionCopyWithImpl<PointPosition>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PointPosition&&const DeepCollectionEquality().equals(other.source, source));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(source));

@override
String toString() {
  return 'Position.point(source: $source)';
}


}

/// @nodoc
abstract mixin class $PointPositionCopyWith<$Res> implements $PositionCopyWith<$Res> {
  factory $PointPositionCopyWith(PointPosition value, $Res Function(PointPosition) _then) = _$PointPositionCopyWithImpl;
@useResult
$Res call({
 Object? source
});




}
/// @nodoc
class _$PointPositionCopyWithImpl<$Res>
    implements $PointPositionCopyWith<$Res> {
  _$PointPositionCopyWithImpl(this._self, this._then);

  final PointPosition _self;
  final $Res Function(PointPosition) _then;

/// Create a copy of Position
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = freezed,}) {
  return _then(PointPosition(
freezed == source ? _self.source : source ,
  ));
}


}

/// @nodoc
mixin _$Document {

 String get schema; Json get meta; Map<String, Frame> get frames; Map<String, Event> get events; Map<String, Pattern> get patterns; Map<String, Relation> get relations; Map<String, Override> get overrides; Json get foreign;
/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentCopyWith<Document> get copyWith => _$DocumentCopyWithImpl<Document>(this as Document, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Document&&(identical(other.schema, schema) || other.schema == schema)&&const DeepCollectionEquality().equals(other.meta, meta)&&const DeepCollectionEquality().equals(other.frames, frames)&&const DeepCollectionEquality().equals(other.events, events)&&const DeepCollectionEquality().equals(other.patterns, patterns)&&const DeepCollectionEquality().equals(other.relations, relations)&&const DeepCollectionEquality().equals(other.overrides, overrides)&&const DeepCollectionEquality().equals(other.foreign, foreign));
}


@override
int get hashCode => Object.hash(runtimeType,schema,const DeepCollectionEquality().hash(meta),const DeepCollectionEquality().hash(frames),const DeepCollectionEquality().hash(events),const DeepCollectionEquality().hash(patterns),const DeepCollectionEquality().hash(relations),const DeepCollectionEquality().hash(overrides),const DeepCollectionEquality().hash(foreign));

@override
String toString() {
  return 'Document(schema: $schema, meta: $meta, frames: $frames, events: $events, patterns: $patterns, relations: $relations, overrides: $overrides, foreign: $foreign)';
}


}

/// @nodoc
abstract mixin class $DocumentCopyWith<$Res>  {
  factory $DocumentCopyWith(Document value, $Res Function(Document) _then) = _$DocumentCopyWithImpl;
@useResult
$Res call({
 String schema, Json meta, Map<String, Frame> frames, Map<String, Event> events, Map<String, Pattern> patterns, Map<String, Relation> relations, Map<String, Override> overrides, Json foreign
});




}
/// @nodoc
class _$DocumentCopyWithImpl<$Res>
    implements $DocumentCopyWith<$Res> {
  _$DocumentCopyWithImpl(this._self, this._then);

  final Document _self;
  final $Res Function(Document) _then;

/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schema = null,Object? meta = null,Object? frames = null,Object? events = null,Object? patterns = null,Object? relations = null,Object? overrides = null,Object? foreign = null,}) {
  return _then(Document(
schema: null == schema ? _self.schema : schema // ignore: cast_nullable_to_non_nullable
as String,meta: null == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Json,frames: null == frames ? _self.frames : frames // ignore: cast_nullable_to_non_nullable
as Map<String, Frame>,events: null == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as Map<String, Event>,patterns: null == patterns ? _self.patterns : patterns // ignore: cast_nullable_to_non_nullable
as Map<String, Pattern>,relations: null == relations ? _self.relations : relations // ignore: cast_nullable_to_non_nullable
as Map<String, Relation>,overrides: null == overrides ? _self.overrides : overrides // ignore: cast_nullable_to_non_nullable
as Map<String, Override>,foreign: null == foreign ? _self.foreign : foreign // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}

}


/// Adds pattern-matching-related methods to [Document].
extension DocumentPatterns on Document {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Document value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Document() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Document value)  $default,){
final _that = this;
switch (_that) {
case _Document():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Document value)?  $default,){
final _that = this;
switch (_that) {
case _Document() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String schema,  Json meta,  Map<String, Frame> frames,  Map<String, Event> events,  Map<String, Pattern> patterns,  Map<String, Relation> relations,  Map<String, Override> overrides,  Json foreign)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Document() when $default != null:
return $default(_that.schema,_that.meta,_that.frames,_that.events,_that.patterns,_that.relations,_that.overrides,_that.foreign);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String schema,  Json meta,  Map<String, Frame> frames,  Map<String, Event> events,  Map<String, Pattern> patterns,  Map<String, Relation> relations,  Map<String, Override> overrides,  Json foreign)  $default,) {final _that = this;
switch (_that) {
case _Document():
return $default(_that.schema,_that.meta,_that.frames,_that.events,_that.patterns,_that.relations,_that.overrides,_that.foreign);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String schema,  Json meta,  Map<String, Frame> frames,  Map<String, Event> events,  Map<String, Pattern> patterns,  Map<String, Relation> relations,  Map<String, Override> overrides,  Json foreign)?  $default,) {final _that = this;
switch (_that) {
case _Document() when $default != null:
return $default(_that.schema,_that.meta,_that.frames,_that.events,_that.patterns,_that.relations,_that.overrides,_that.foreign);case _:
  return null;

}
}

}

/// @nodoc


class _Document extends Document {
  const _Document({this.schema = schemaVersion,  Json meta = const <String, dynamic>{},  Map<String, Frame> frames = const <String, Frame>{},  Map<String, Event> events = const <String, Event>{},  Map<String, Pattern> patterns = const <String, Pattern>{},  Map<String, Relation> relations = const <String, Relation>{},  Map<String, Override> overrides = const <String, Override>{},  Json foreign = const <String, dynamic>{}}): _meta = meta,_frames = frames,_events = events,_patterns = patterns,_relations = relations,_overrides = overrides,_foreign = foreign,super._();
  

@override@JsonKey() final  String schema;
 final  Json _meta;
@override@JsonKey() Json get meta {
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_meta);
}

 final  Map<String, Frame> _frames;
@override@JsonKey() Map<String, Frame> get frames {
  if (_frames is EqualUnmodifiableMapView) return _frames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_frames);
}

 final  Map<String, Event> _events;
@override@JsonKey() Map<String, Event> get events {
  if (_events is EqualUnmodifiableMapView) return _events;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_events);
}

 final  Map<String, Pattern> _patterns;
@override@JsonKey() Map<String, Pattern> get patterns {
  if (_patterns is EqualUnmodifiableMapView) return _patterns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_patterns);
}

 final  Map<String, Relation> _relations;
@override@JsonKey() Map<String, Relation> get relations {
  if (_relations is EqualUnmodifiableMapView) return _relations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_relations);
}

 final  Map<String, Override> _overrides;
@override@JsonKey() Map<String, Override> get overrides {
  if (_overrides is EqualUnmodifiableMapView) return _overrides;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_overrides);
}

 final  Json _foreign;
@override@JsonKey() Json get foreign {
  if (_foreign is EqualUnmodifiableMapView) return _foreign;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_foreign);
}


/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentCopyWith<_Document> get copyWith => __$DocumentCopyWithImpl<_Document>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Document&&(identical(other.schema, schema) || other.schema == schema)&&const DeepCollectionEquality().equals(other._meta, _meta)&&const DeepCollectionEquality().equals(other._frames, _frames)&&const DeepCollectionEquality().equals(other._events, _events)&&const DeepCollectionEquality().equals(other._patterns, _patterns)&&const DeepCollectionEquality().equals(other._relations, _relations)&&const DeepCollectionEquality().equals(other._overrides, _overrides)&&const DeepCollectionEquality().equals(other._foreign, _foreign));
}


@override
int get hashCode => Object.hash(runtimeType,schema,const DeepCollectionEquality().hash(_meta),const DeepCollectionEquality().hash(_frames),const DeepCollectionEquality().hash(_events),const DeepCollectionEquality().hash(_patterns),const DeepCollectionEquality().hash(_relations),const DeepCollectionEquality().hash(_overrides),const DeepCollectionEquality().hash(_foreign));

@override
String toString() {
  return 'Document(schema: $schema, meta: $meta, frames: $frames, events: $events, patterns: $patterns, relations: $relations, overrides: $overrides, foreign: $foreign)';
}


}

/// @nodoc
abstract mixin class _$DocumentCopyWith<$Res> implements $DocumentCopyWith<$Res> {
  factory _$DocumentCopyWith(_Document value, $Res Function(_Document) _then) = __$DocumentCopyWithImpl;
@override @useResult
$Res call({
 String schema, Json meta, Map<String, Frame> frames, Map<String, Event> events, Map<String, Pattern> patterns, Map<String, Relation> relations, Map<String, Override> overrides, Json foreign
});




}
/// @nodoc
class __$DocumentCopyWithImpl<$Res>
    implements _$DocumentCopyWith<$Res> {
  __$DocumentCopyWithImpl(this._self, this._then);

  final _Document _self;
  final $Res Function(_Document) _then;

/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schema = null,Object? meta = null,Object? frames = null,Object? events = null,Object? patterns = null,Object? relations = null,Object? overrides = null,Object? foreign = null,}) {
  return _then(_Document(
schema: null == schema ? _self.schema : schema // ignore: cast_nullable_to_non_nullable
as String,meta: null == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Json,frames: null == frames ? _self._frames : frames // ignore: cast_nullable_to_non_nullable
as Map<String, Frame>,events: null == events ? _self._events : events // ignore: cast_nullable_to_non_nullable
as Map<String, Event>,patterns: null == patterns ? _self._patterns : patterns // ignore: cast_nullable_to_non_nullable
as Map<String, Pattern>,relations: null == relations ? _self._relations : relations // ignore: cast_nullable_to_non_nullable
as Map<String, Relation>,overrides: null == overrides ? _self._overrides : overrides // ignore: cast_nullable_to_non_nullable
as Map<String, Override>,foreign: null == foreign ? _self._foreign : foreign // ignore: cast_nullable_to_non_nullable
as Json,
  ));
}


}

// dart format on
