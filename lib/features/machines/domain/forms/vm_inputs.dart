import 'package:formz/formz.dart';

/// Validation errors for [VmNameInput].
enum VmNameError { empty, tooLong, invalidCharacters }

/// VM name: becomes a directory and `<name>.conf`, so it must be a single
/// safe path component (no separators, no leading dot or dash).
class VmNameInput extends FormzInput<String, VmNameError> {
  const VmNameInput.pure([super.value = '']) : super.pure();
  const VmNameInput.dirty([super.value = '']) : super.dirty();

  static const maxLength = 64;
  static final _pattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]*$');

  @override
  VmNameError? validator(String value) {
    final v = value.trim();
    if (v.isEmpty) return VmNameError.empty;
    if (v.length > maxLength) return VmNameError.tooLong;
    if (!_pattern.hasMatch(v)) return VmNameError.invalidCharacters;
    return null;
  }
}

/// Validation errors for size inputs (RAM, disk).
enum SizeError { empty, invalidFormat }

/// A quickemu size such as `4G`, `4096M` or `1T`. When [optional] is true
/// an empty value is valid (meaning "use quickemu's default").
class SizeInput extends FormzInput<String, SizeError> {
  const SizeInput.pure([super.value = '', this.optional = false])
    : super.pure();
  const SizeInput.dirty([super.value = '', this.optional = false])
    : super.dirty();

  final bool optional;
  static final _pattern = RegExp(r'^[1-9][0-9]*(\.[0-9]+)?[KMGT]?$');

  @override
  SizeError? validator(String value) {
    final v = value.trim().toUpperCase();
    if (v.isEmpty) return optional ? null : SizeError.empty;
    return _pattern.hasMatch(v) ? null : SizeError.invalidFormat;
  }
}

/// Validation errors for [CpuCoresInput].
enum CpuCoresError { notANumber, outOfRange }

/// CPU cores: optional; when set must be an integer in 1..[max].
class CpuCoresInput extends FormzInput<String, CpuCoresError> {
  const CpuCoresInput.pure([super.value = '']) : super.pure();
  const CpuCoresInput.dirty([super.value = '']) : super.dirty();

  static const max = 256;

  @override
  CpuCoresError? validator(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null) return CpuCoresError.notANumber;
    return n < 1 || n > max ? CpuCoresError.outOfRange : null;
  }
}

enum NonEmptyError { empty }

/// Free-form text that only requires a non-empty value.
class NonEmptyInput extends FormzInput<String, NonEmptyError> {
  const NonEmptyInput.pure() : super.pure('');
  const NonEmptyInput.dirty(super.value) : super.dirty();

  @override
  NonEmptyError? validator(String value) =>
      value.trim().isEmpty ? NonEmptyError.empty : null;
}
