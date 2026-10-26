// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'operation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$OperationState<T> {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationState<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>()';
}


}

/// @nodoc
class $OperationStateCopyWith<T,$Res>  {
$OperationStateCopyWith(OperationState<T> _, $Res Function(OperationState<T>) __);
}


/// Adds pattern-matching-related methods to [OperationState].
extension OperationStatePatterns<T> on OperationState<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OperationIdle<T> value)?  idle,TResult Function( OperationValidating<T> value)?  validating,TResult Function( OperationWaitingForConfirmation<T> value)?  waitingForConfirmation,TResult Function( OperationQueued<T> value)?  queued,TResult Function( OperationRunning<T> value)?  running,TResult Function( OperationPaused<T> value)?  paused,TResult Function( OperationCancelling<T> value)?  cancelling,TResult Function( OperationCancelled<T> value)?  cancelled,TResult Function( OperationSucceeded<T> value)?  succeeded,TResult Function( OperationFailed<T> value)?  failed,TResult Function( OperationInterrupted<T> value)?  interrupted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OperationIdle() when idle != null:
return idle(_that);case OperationValidating() when validating != null:
return validating(_that);case OperationWaitingForConfirmation() when waitingForConfirmation != null:
return waitingForConfirmation(_that);case OperationQueued() when queued != null:
return queued(_that);case OperationRunning() when running != null:
return running(_that);case OperationPaused() when paused != null:
return paused(_that);case OperationCancelling() when cancelling != null:
return cancelling(_that);case OperationCancelled() when cancelled != null:
return cancelled(_that);case OperationSucceeded() when succeeded != null:
return succeeded(_that);case OperationFailed() when failed != null:
return failed(_that);case OperationInterrupted() when interrupted != null:
return interrupted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OperationIdle<T> value)  idle,required TResult Function( OperationValidating<T> value)  validating,required TResult Function( OperationWaitingForConfirmation<T> value)  waitingForConfirmation,required TResult Function( OperationQueued<T> value)  queued,required TResult Function( OperationRunning<T> value)  running,required TResult Function( OperationPaused<T> value)  paused,required TResult Function( OperationCancelling<T> value)  cancelling,required TResult Function( OperationCancelled<T> value)  cancelled,required TResult Function( OperationSucceeded<T> value)  succeeded,required TResult Function( OperationFailed<T> value)  failed,required TResult Function( OperationInterrupted<T> value)  interrupted,}){
final _that = this;
switch (_that) {
case OperationIdle():
return idle(_that);case OperationValidating():
return validating(_that);case OperationWaitingForConfirmation():
return waitingForConfirmation(_that);case OperationQueued():
return queued(_that);case OperationRunning():
return running(_that);case OperationPaused():
return paused(_that);case OperationCancelling():
return cancelling(_that);case OperationCancelled():
return cancelled(_that);case OperationSucceeded():
return succeeded(_that);case OperationFailed():
return failed(_that);case OperationInterrupted():
return interrupted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OperationIdle<T> value)?  idle,TResult? Function( OperationValidating<T> value)?  validating,TResult? Function( OperationWaitingForConfirmation<T> value)?  waitingForConfirmation,TResult? Function( OperationQueued<T> value)?  queued,TResult? Function( OperationRunning<T> value)?  running,TResult? Function( OperationPaused<T> value)?  paused,TResult? Function( OperationCancelling<T> value)?  cancelling,TResult? Function( OperationCancelled<T> value)?  cancelled,TResult? Function( OperationSucceeded<T> value)?  succeeded,TResult? Function( OperationFailed<T> value)?  failed,TResult? Function( OperationInterrupted<T> value)?  interrupted,}){
final _that = this;
switch (_that) {
case OperationIdle() when idle != null:
return idle(_that);case OperationValidating() when validating != null:
return validating(_that);case OperationWaitingForConfirmation() when waitingForConfirmation != null:
return waitingForConfirmation(_that);case OperationQueued() when queued != null:
return queued(_that);case OperationRunning() when running != null:
return running(_that);case OperationPaused() when paused != null:
return paused(_that);case OperationCancelling() when cancelling != null:
return cancelling(_that);case OperationCancelled() when cancelled != null:
return cancelled(_that);case OperationSucceeded() when succeeded != null:
return succeeded(_that);case OperationFailed() when failed != null:
return failed(_that);case OperationInterrupted() when interrupted != null:
return interrupted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  validating,TResult Function()?  waitingForConfirmation,TResult Function()?  queued,TResult Function( double? progress,  String? line)?  running,TResult Function( double? progress,  String? line)?  paused,TResult Function()?  cancelling,TResult Function()?  cancelled,TResult Function( T value)?  succeeded,TResult Function( String code,  String message,  bool retryable)?  failed,TResult Function()?  interrupted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OperationIdle() when idle != null:
return idle();case OperationValidating() when validating != null:
return validating();case OperationWaitingForConfirmation() when waitingForConfirmation != null:
return waitingForConfirmation();case OperationQueued() when queued != null:
return queued();case OperationRunning() when running != null:
return running(_that.progress,_that.line);case OperationPaused() when paused != null:
return paused(_that.progress,_that.line);case OperationCancelling() when cancelling != null:
return cancelling();case OperationCancelled() when cancelled != null:
return cancelled();case OperationSucceeded() when succeeded != null:
return succeeded(_that.value);case OperationFailed() when failed != null:
return failed(_that.code,_that.message,_that.retryable);case OperationInterrupted() when interrupted != null:
return interrupted();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  validating,required TResult Function()  waitingForConfirmation,required TResult Function()  queued,required TResult Function( double? progress,  String? line)  running,required TResult Function( double? progress,  String? line)  paused,required TResult Function()  cancelling,required TResult Function()  cancelled,required TResult Function( T value)  succeeded,required TResult Function( String code,  String message,  bool retryable)  failed,required TResult Function()  interrupted,}) {final _that = this;
switch (_that) {
case OperationIdle():
return idle();case OperationValidating():
return validating();case OperationWaitingForConfirmation():
return waitingForConfirmation();case OperationQueued():
return queued();case OperationRunning():
return running(_that.progress,_that.line);case OperationPaused():
return paused(_that.progress,_that.line);case OperationCancelling():
return cancelling();case OperationCancelled():
return cancelled();case OperationSucceeded():
return succeeded(_that.value);case OperationFailed():
return failed(_that.code,_that.message,_that.retryable);case OperationInterrupted():
return interrupted();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  validating,TResult? Function()?  waitingForConfirmation,TResult? Function()?  queued,TResult? Function( double? progress,  String? line)?  running,TResult? Function( double? progress,  String? line)?  paused,TResult? Function()?  cancelling,TResult? Function()?  cancelled,TResult? Function( T value)?  succeeded,TResult? Function( String code,  String message,  bool retryable)?  failed,TResult? Function()?  interrupted,}) {final _that = this;
switch (_that) {
case OperationIdle() when idle != null:
return idle();case OperationValidating() when validating != null:
return validating();case OperationWaitingForConfirmation() when waitingForConfirmation != null:
return waitingForConfirmation();case OperationQueued() when queued != null:
return queued();case OperationRunning() when running != null:
return running(_that.progress,_that.line);case OperationPaused() when paused != null:
return paused(_that.progress,_that.line);case OperationCancelling() when cancelling != null:
return cancelling();case OperationCancelled() when cancelled != null:
return cancelled();case OperationSucceeded() when succeeded != null:
return succeeded(_that.value);case OperationFailed() when failed != null:
return failed(_that.code,_that.message,_that.retryable);case OperationInterrupted() when interrupted != null:
return interrupted();case _:
  return null;

}
}

}

/// @nodoc


class OperationIdle<T> extends OperationState<T> {
  const OperationIdle(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationIdle<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.idle()';
}


}




/// @nodoc


class OperationValidating<T> extends OperationState<T> {
  const OperationValidating(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationValidating<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.validating()';
}


}




/// @nodoc


class OperationWaitingForConfirmation<T> extends OperationState<T> {
  const OperationWaitingForConfirmation(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationWaitingForConfirmation<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.waitingForConfirmation()';
}


}




/// @nodoc


class OperationQueued<T> extends OperationState<T> {
  const OperationQueued(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationQueued<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.queued()';
}


}




/// @nodoc


class OperationRunning<T> extends OperationState<T> {
  const OperationRunning({this.progress, this.line}): super._();
  

 final  double? progress;
 final  String? line;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationRunningCopyWith<T, OperationRunning<T>> get copyWith => _$OperationRunningCopyWithImpl<T, OperationRunning<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationRunning<T>&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.line, line) || other.line == line));
}


@override
int get hashCode => Object.hash(runtimeType,progress,line);

@override
String toString() {
  return 'OperationState<$T>.running(progress: $progress, line: $line)';
}


}

/// @nodoc
abstract mixin class $OperationRunningCopyWith<T,$Res> implements $OperationStateCopyWith<T, $Res> {
  factory $OperationRunningCopyWith(OperationRunning<T> value, $Res Function(OperationRunning<T>) _then) = _$OperationRunningCopyWithImpl;
@useResult
$Res call({
 double? progress, String? line
});




}
/// @nodoc
class _$OperationRunningCopyWithImpl<T,$Res>
    implements $OperationRunningCopyWith<T, $Res> {
  _$OperationRunningCopyWithImpl(this._self, this._then);

  final OperationRunning<T> _self;
  final $Res Function(OperationRunning<T>) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = freezed,Object? line = freezed,}) {
  return _then(OperationRunning<T>(
progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,line: freezed == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class OperationPaused<T> extends OperationState<T> {
  const OperationPaused({this.progress, this.line}): super._();
  

 final  double? progress;
 final  String? line;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationPausedCopyWith<T, OperationPaused<T>> get copyWith => _$OperationPausedCopyWithImpl<T, OperationPaused<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationPaused<T>&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.line, line) || other.line == line));
}


@override
int get hashCode => Object.hash(runtimeType,progress,line);

@override
String toString() {
  return 'OperationState<$T>.paused(progress: $progress, line: $line)';
}


}

/// @nodoc
abstract mixin class $OperationPausedCopyWith<T,$Res> implements $OperationStateCopyWith<T, $Res> {
  factory $OperationPausedCopyWith(OperationPaused<T> value, $Res Function(OperationPaused<T>) _then) = _$OperationPausedCopyWithImpl;
@useResult
$Res call({
 double? progress, String? line
});




}
/// @nodoc
class _$OperationPausedCopyWithImpl<T,$Res>
    implements $OperationPausedCopyWith<T, $Res> {
  _$OperationPausedCopyWithImpl(this._self, this._then);

  final OperationPaused<T> _self;
  final $Res Function(OperationPaused<T>) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = freezed,Object? line = freezed,}) {
  return _then(OperationPaused<T>(
progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,line: freezed == line ? _self.line : line // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class OperationCancelling<T> extends OperationState<T> {
  const OperationCancelling(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationCancelling<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.cancelling()';
}


}




/// @nodoc


class OperationCancelled<T> extends OperationState<T> {
  const OperationCancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationCancelled<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.cancelled()';
}


}




/// @nodoc


class OperationSucceeded<T> extends OperationState<T> {
  const OperationSucceeded(this.value): super._();
  

 final  T value;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationSucceededCopyWith<T, OperationSucceeded<T>> get copyWith => _$OperationSucceededCopyWithImpl<T, OperationSucceeded<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationSucceeded<T>&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'OperationState<$T>.succeeded(value: $value)';
}


}

/// @nodoc
abstract mixin class $OperationSucceededCopyWith<T,$Res> implements $OperationStateCopyWith<T, $Res> {
  factory $OperationSucceededCopyWith(OperationSucceeded<T> value, $Res Function(OperationSucceeded<T>) _then) = _$OperationSucceededCopyWithImpl;
@useResult
$Res call({
 T value
});




}
/// @nodoc
class _$OperationSucceededCopyWithImpl<T,$Res>
    implements $OperationSucceededCopyWith<T, $Res> {
  _$OperationSucceededCopyWithImpl(this._self, this._then);

  final OperationSucceeded<T> _self;
  final $Res Function(OperationSucceeded<T>) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(OperationSucceeded<T>(
freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class OperationFailed<T> extends OperationState<T> {
  const OperationFailed({required this.code, required this.message, this.retryable = false}): super._();
  

 final  String code;
 final  String message;
@JsonKey() final  bool retryable;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationFailedCopyWith<T, OperationFailed<T>> get copyWith => _$OperationFailedCopyWithImpl<T, OperationFailed<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationFailed<T>&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode => Object.hash(runtimeType,code,message,retryable);

@override
String toString() {
  return 'OperationState<$T>.failed(code: $code, message: $message, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $OperationFailedCopyWith<T,$Res> implements $OperationStateCopyWith<T, $Res> {
  factory $OperationFailedCopyWith(OperationFailed<T> value, $Res Function(OperationFailed<T>) _then) = _$OperationFailedCopyWithImpl;
@useResult
$Res call({
 String code, String message, bool retryable
});




}
/// @nodoc
class _$OperationFailedCopyWithImpl<T,$Res>
    implements $OperationFailedCopyWith<T, $Res> {
  _$OperationFailedCopyWithImpl(this._self, this._then);

  final OperationFailed<T> _self;
  final $Res Function(OperationFailed<T>) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(OperationFailed<T>(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class OperationInterrupted<T> extends OperationState<T> {
  const OperationInterrupted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationInterrupted<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OperationState<$T>.interrupted()';
}


}




// dart format on
