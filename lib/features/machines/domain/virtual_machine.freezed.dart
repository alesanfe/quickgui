// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'virtual_machine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$VirtualMachine {

 String get name;@JsonKey(name: 'guest_os') String? get guestOs;@JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson) VmStatus get status; int? get pid;
/// Create a copy of VirtualMachine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VirtualMachineCopyWith<VirtualMachine> get copyWith => _$VirtualMachineCopyWithImpl<VirtualMachine>(this as VirtualMachine, _$identity);

  /// Serializes this VirtualMachine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VirtualMachine&&(identical(other.name, name) || other.name == name)&&(identical(other.guestOs, guestOs) || other.guestOs == guestOs)&&(identical(other.status, status) || other.status == status)&&(identical(other.pid, pid) || other.pid == pid));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,guestOs,status,pid);

@override
String toString() {
  return 'VirtualMachine(name: $name, guestOs: $guestOs, status: $status, pid: $pid)';
}


}

/// @nodoc
abstract mixin class $VirtualMachineCopyWith<$Res>  {
  factory $VirtualMachineCopyWith(VirtualMachine value, $Res Function(VirtualMachine) _then) = _$VirtualMachineCopyWithImpl;
@useResult
$Res call({
 String name,@JsonKey(name: 'guest_os') String? guestOs,@JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson) VmStatus status, int? pid
});




}
/// @nodoc
class _$VirtualMachineCopyWithImpl<$Res>
    implements $VirtualMachineCopyWith<$Res> {
  _$VirtualMachineCopyWithImpl(this._self, this._then);

  final VirtualMachine _self;
  final $Res Function(VirtualMachine) _then;

/// Create a copy of VirtualMachine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? guestOs = freezed,Object? status = null,Object? pid = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,guestOs: freezed == guestOs ? _self.guestOs : guestOs // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as VmStatus,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [VirtualMachine].
extension VirtualMachinePatterns on VirtualMachine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VirtualMachine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VirtualMachine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VirtualMachine value)  $default,){
final _that = this;
switch (_that) {
case _VirtualMachine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VirtualMachine value)?  $default,){
final _that = this;
switch (_that) {
case _VirtualMachine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name, @JsonKey(name: 'guest_os')  String? guestOs, @JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson)  VmStatus status,  int? pid)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VirtualMachine() when $default != null:
return $default(_that.name,_that.guestOs,_that.status,_that.pid);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name, @JsonKey(name: 'guest_os')  String? guestOs, @JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson)  VmStatus status,  int? pid)  $default,) {final _that = this;
switch (_that) {
case _VirtualMachine():
return $default(_that.name,_that.guestOs,_that.status,_that.pid);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name, @JsonKey(name: 'guest_os')  String? guestOs, @JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson)  VmStatus status,  int? pid)?  $default,) {final _that = this;
switch (_that) {
case _VirtualMachine() when $default != null:
return $default(_that.name,_that.guestOs,_that.status,_that.pid);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _VirtualMachine extends VirtualMachine {
  const _VirtualMachine({required this.name, @JsonKey(name: 'guest_os') this.guestOs, @JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson) this.status = VmStatus.unknown, this.pid}): super._();
  factory _VirtualMachine.fromJson(Map<String, dynamic> json) => _$VirtualMachineFromJson(json);

@override final  String name;
@override@JsonKey(name: 'guest_os') final  String? guestOs;
@override@JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson) final  VmStatus status;
@override final  int? pid;

/// Create a copy of VirtualMachine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VirtualMachineCopyWith<_VirtualMachine> get copyWith => __$VirtualMachineCopyWithImpl<_VirtualMachine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VirtualMachineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VirtualMachine&&(identical(other.name, name) || other.name == name)&&(identical(other.guestOs, guestOs) || other.guestOs == guestOs)&&(identical(other.status, status) || other.status == status)&&(identical(other.pid, pid) || other.pid == pid));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,guestOs,status,pid);

@override
String toString() {
  return 'VirtualMachine(name: $name, guestOs: $guestOs, status: $status, pid: $pid)';
}


}

/// @nodoc
abstract mixin class _$VirtualMachineCopyWith<$Res> implements $VirtualMachineCopyWith<$Res> {
  factory _$VirtualMachineCopyWith(_VirtualMachine value, $Res Function(_VirtualMachine) _then) = __$VirtualMachineCopyWithImpl;
@override @useResult
$Res call({
 String name,@JsonKey(name: 'guest_os') String? guestOs,@JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson) VmStatus status, int? pid
});




}
/// @nodoc
class __$VirtualMachineCopyWithImpl<$Res>
    implements _$VirtualMachineCopyWith<$Res> {
  __$VirtualMachineCopyWithImpl(this._self, this._then);

  final _VirtualMachine _self;
  final $Res Function(_VirtualMachine) _then;

/// Create a copy of VirtualMachine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? guestOs = freezed,Object? status = null,Object? pid = freezed,}) {
  return _then(_VirtualMachine(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,guestOs: freezed == guestOs ? _self.guestOs : guestOs // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as VmStatus,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
