// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'diagnostics_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DiagnosticsReport {

 String get quickguiVersion; bool get backendAvailable; bool get kvmAvailable; String get workingDirectory; String? get backendVersion; int? get contractVersion; Map<String, bool> get capabilities; Map<String, bool> get tools; int? get freeSpaceBytes; List<Map<String, dynamic>> get recentErrors; List<Map<String, dynamic>> get legacyFallbacks;
/// Create a copy of DiagnosticsReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsReportCopyWith<DiagnosticsReport> get copyWith => _$DiagnosticsReportCopyWithImpl<DiagnosticsReport>(this as DiagnosticsReport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsReport&&(identical(other.quickguiVersion, quickguiVersion) || other.quickguiVersion == quickguiVersion)&&(identical(other.backendAvailable, backendAvailable) || other.backendAvailable == backendAvailable)&&(identical(other.kvmAvailable, kvmAvailable) || other.kvmAvailable == kvmAvailable)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.backendVersion, backendVersion) || other.backendVersion == backendVersion)&&(identical(other.contractVersion, contractVersion) || other.contractVersion == contractVersion)&&const DeepCollectionEquality().equals(other.capabilities, capabilities)&&const DeepCollectionEquality().equals(other.tools, tools)&&(identical(other.freeSpaceBytes, freeSpaceBytes) || other.freeSpaceBytes == freeSpaceBytes)&&const DeepCollectionEquality().equals(other.recentErrors, recentErrors)&&const DeepCollectionEquality().equals(other.legacyFallbacks, legacyFallbacks));
}


@override
int get hashCode => Object.hash(runtimeType,quickguiVersion,backendAvailable,kvmAvailable,workingDirectory,backendVersion,contractVersion,const DeepCollectionEquality().hash(capabilities),const DeepCollectionEquality().hash(tools),freeSpaceBytes,const DeepCollectionEquality().hash(recentErrors),const DeepCollectionEquality().hash(legacyFallbacks));

@override
String toString() {
  return 'DiagnosticsReport(quickguiVersion: $quickguiVersion, backendAvailable: $backendAvailable, kvmAvailable: $kvmAvailable, workingDirectory: $workingDirectory, backendVersion: $backendVersion, contractVersion: $contractVersion, capabilities: $capabilities, tools: $tools, freeSpaceBytes: $freeSpaceBytes, recentErrors: $recentErrors, legacyFallbacks: $legacyFallbacks)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsReportCopyWith<$Res>  {
  factory $DiagnosticsReportCopyWith(DiagnosticsReport value, $Res Function(DiagnosticsReport) _then) = _$DiagnosticsReportCopyWithImpl;
@useResult
$Res call({
 String quickguiVersion, bool backendAvailable, bool kvmAvailable, String workingDirectory, String? backendVersion, int? contractVersion, Map<String, bool> capabilities, Map<String, bool> tools, int? freeSpaceBytes, List<Map<String, dynamic>> recentErrors, List<Map<String, dynamic>> legacyFallbacks
});




}
/// @nodoc
class _$DiagnosticsReportCopyWithImpl<$Res>
    implements $DiagnosticsReportCopyWith<$Res> {
  _$DiagnosticsReportCopyWithImpl(this._self, this._then);

  final DiagnosticsReport _self;
  final $Res Function(DiagnosticsReport) _then;

/// Create a copy of DiagnosticsReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? quickguiVersion = null,Object? backendAvailable = null,Object? kvmAvailable = null,Object? workingDirectory = null,Object? backendVersion = freezed,Object? contractVersion = freezed,Object? capabilities = null,Object? tools = null,Object? freeSpaceBytes = freezed,Object? recentErrors = null,Object? legacyFallbacks = null,}) {
  return _then(_self.copyWith(
quickguiVersion: null == quickguiVersion ? _self.quickguiVersion : quickguiVersion // ignore: cast_nullable_to_non_nullable
as String,backendAvailable: null == backendAvailable ? _self.backendAvailable : backendAvailable // ignore: cast_nullable_to_non_nullable
as bool,kvmAvailable: null == kvmAvailable ? _self.kvmAvailable : kvmAvailable // ignore: cast_nullable_to_non_nullable
as bool,workingDirectory: null == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String,backendVersion: freezed == backendVersion ? _self.backendVersion : backendVersion // ignore: cast_nullable_to_non_nullable
as String?,contractVersion: freezed == contractVersion ? _self.contractVersion : contractVersion // ignore: cast_nullable_to_non_nullable
as int?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,tools: null == tools ? _self.tools : tools // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,freeSpaceBytes: freezed == freeSpaceBytes ? _self.freeSpaceBytes : freeSpaceBytes // ignore: cast_nullable_to_non_nullable
as int?,recentErrors: null == recentErrors ? _self.recentErrors : recentErrors // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,legacyFallbacks: null == legacyFallbacks ? _self.legacyFallbacks : legacyFallbacks // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosticsReport].
extension DiagnosticsReportPatterns on DiagnosticsReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosticsReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosticsReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosticsReport value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosticsReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosticsReport value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosticsReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String quickguiVersion,  bool backendAvailable,  bool kvmAvailable,  String workingDirectory,  String? backendVersion,  int? contractVersion,  Map<String, bool> capabilities,  Map<String, bool> tools,  int? freeSpaceBytes,  List<Map<String, dynamic>> recentErrors,  List<Map<String, dynamic>> legacyFallbacks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiagnosticsReport() when $default != null:
return $default(_that.quickguiVersion,_that.backendAvailable,_that.kvmAvailable,_that.workingDirectory,_that.backendVersion,_that.contractVersion,_that.capabilities,_that.tools,_that.freeSpaceBytes,_that.recentErrors,_that.legacyFallbacks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String quickguiVersion,  bool backendAvailable,  bool kvmAvailable,  String workingDirectory,  String? backendVersion,  int? contractVersion,  Map<String, bool> capabilities,  Map<String, bool> tools,  int? freeSpaceBytes,  List<Map<String, dynamic>> recentErrors,  List<Map<String, dynamic>> legacyFallbacks)  $default,) {final _that = this;
switch (_that) {
case _DiagnosticsReport():
return $default(_that.quickguiVersion,_that.backendAvailable,_that.kvmAvailable,_that.workingDirectory,_that.backendVersion,_that.contractVersion,_that.capabilities,_that.tools,_that.freeSpaceBytes,_that.recentErrors,_that.legacyFallbacks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String quickguiVersion,  bool backendAvailable,  bool kvmAvailable,  String workingDirectory,  String? backendVersion,  int? contractVersion,  Map<String, bool> capabilities,  Map<String, bool> tools,  int? freeSpaceBytes,  List<Map<String, dynamic>> recentErrors,  List<Map<String, dynamic>> legacyFallbacks)?  $default,) {final _that = this;
switch (_that) {
case _DiagnosticsReport() when $default != null:
return $default(_that.quickguiVersion,_that.backendAvailable,_that.kvmAvailable,_that.workingDirectory,_that.backendVersion,_that.contractVersion,_that.capabilities,_that.tools,_that.freeSpaceBytes,_that.recentErrors,_that.legacyFallbacks);case _:
  return null;

}
}

}

/// @nodoc


class _DiagnosticsReport extends DiagnosticsReport {
  const _DiagnosticsReport({required this.quickguiVersion, required this.backendAvailable, required this.kvmAvailable, required this.workingDirectory, this.backendVersion, this.contractVersion, this.capabilities = const <String, bool>{}, this.tools = const <String, bool>{}, this.freeSpaceBytes, this.recentErrors = const <Map<String, dynamic>>[], this.legacyFallbacks = const <Map<String, dynamic>>[]}): super._();
  

@override final  String quickguiVersion;
@override final  bool backendAvailable;
@override final  bool kvmAvailable;
@override final  String workingDirectory;
@override final  String? backendVersion;
@override final  int? contractVersion;
@override@JsonKey() final  Map<String, bool> capabilities;
@override@JsonKey() final  Map<String, bool> tools;
@override final  int? freeSpaceBytes;
@override@JsonKey() final  List<Map<String, dynamic>> recentErrors;
@override@JsonKey() final  List<Map<String, dynamic>> legacyFallbacks;

/// Create a copy of DiagnosticsReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosticsReportCopyWith<_DiagnosticsReport> get copyWith => __$DiagnosticsReportCopyWithImpl<_DiagnosticsReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosticsReport&&(identical(other.quickguiVersion, quickguiVersion) || other.quickguiVersion == quickguiVersion)&&(identical(other.backendAvailable, backendAvailable) || other.backendAvailable == backendAvailable)&&(identical(other.kvmAvailable, kvmAvailable) || other.kvmAvailable == kvmAvailable)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.backendVersion, backendVersion) || other.backendVersion == backendVersion)&&(identical(other.contractVersion, contractVersion) || other.contractVersion == contractVersion)&&const DeepCollectionEquality().equals(other.capabilities, capabilities)&&const DeepCollectionEquality().equals(other.tools, tools)&&(identical(other.freeSpaceBytes, freeSpaceBytes) || other.freeSpaceBytes == freeSpaceBytes)&&const DeepCollectionEquality().equals(other.recentErrors, recentErrors)&&const DeepCollectionEquality().equals(other.legacyFallbacks, legacyFallbacks));
}


@override
int get hashCode => Object.hash(runtimeType,quickguiVersion,backendAvailable,kvmAvailable,workingDirectory,backendVersion,contractVersion,const DeepCollectionEquality().hash(capabilities),const DeepCollectionEquality().hash(tools),freeSpaceBytes,const DeepCollectionEquality().hash(recentErrors),const DeepCollectionEquality().hash(legacyFallbacks));

@override
String toString() {
  return 'DiagnosticsReport(quickguiVersion: $quickguiVersion, backendAvailable: $backendAvailable, kvmAvailable: $kvmAvailable, workingDirectory: $workingDirectory, backendVersion: $backendVersion, contractVersion: $contractVersion, capabilities: $capabilities, tools: $tools, freeSpaceBytes: $freeSpaceBytes, recentErrors: $recentErrors, legacyFallbacks: $legacyFallbacks)';
}


}

/// @nodoc
abstract mixin class _$DiagnosticsReportCopyWith<$Res> implements $DiagnosticsReportCopyWith<$Res> {
  factory _$DiagnosticsReportCopyWith(_DiagnosticsReport value, $Res Function(_DiagnosticsReport) _then) = __$DiagnosticsReportCopyWithImpl;
@override @useResult
$Res call({
 String quickguiVersion, bool backendAvailable, bool kvmAvailable, String workingDirectory, String? backendVersion, int? contractVersion, Map<String, bool> capabilities, Map<String, bool> tools, int? freeSpaceBytes, List<Map<String, dynamic>> recentErrors, List<Map<String, dynamic>> legacyFallbacks
});




}
/// @nodoc
class __$DiagnosticsReportCopyWithImpl<$Res>
    implements _$DiagnosticsReportCopyWith<$Res> {
  __$DiagnosticsReportCopyWithImpl(this._self, this._then);

  final _DiagnosticsReport _self;
  final $Res Function(_DiagnosticsReport) _then;

/// Create a copy of DiagnosticsReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? quickguiVersion = null,Object? backendAvailable = null,Object? kvmAvailable = null,Object? workingDirectory = null,Object? backendVersion = freezed,Object? contractVersion = freezed,Object? capabilities = null,Object? tools = null,Object? freeSpaceBytes = freezed,Object? recentErrors = null,Object? legacyFallbacks = null,}) {
  return _then(_DiagnosticsReport(
quickguiVersion: null == quickguiVersion ? _self.quickguiVersion : quickguiVersion // ignore: cast_nullable_to_non_nullable
as String,backendAvailable: null == backendAvailable ? _self.backendAvailable : backendAvailable // ignore: cast_nullable_to_non_nullable
as bool,kvmAvailable: null == kvmAvailable ? _self.kvmAvailable : kvmAvailable // ignore: cast_nullable_to_non_nullable
as bool,workingDirectory: null == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String,backendVersion: freezed == backendVersion ? _self.backendVersion : backendVersion // ignore: cast_nullable_to_non_nullable
as String?,contractVersion: freezed == contractVersion ? _self.contractVersion : contractVersion // ignore: cast_nullable_to_non_nullable
as int?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,tools: null == tools ? _self.tools : tools // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,freeSpaceBytes: freezed == freeSpaceBytes ? _self.freeSpaceBytes : freeSpaceBytes // ignore: cast_nullable_to_non_nullable
as int?,recentErrors: null == recentErrors ? _self.recentErrors : recentErrors // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,legacyFallbacks: null == legacyFallbacks ? _self.legacyFallbacks : legacyFallbacks // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,
  ));
}


}

// dart format on
