import 'package:freezed_annotation/freezed_annotation.dart';

part 'diagnostics_report.freezed.dart';

/// Local, private diagnostics snapshot (plan section 3.14). Never sent
/// anywhere; [toSanitizedText] is what the user may copy into a bug report.
// Collections stay plain: Freezed 3.2's unmodifiable wrappers emit `final`
// parameters that Dart 3.13 rejects.
@Freezed(makeCollectionsUnmodifiable: false)
abstract class DiagnosticsReport with _$DiagnosticsReport {
  const DiagnosticsReport._();

  const factory DiagnosticsReport({
    required String quickguiVersion,
    required bool backendAvailable,
    required bool kvmAvailable,
    required String workingDirectory,
    String? backendVersion,
    int? contractVersion,
    @Default(<String, bool>{}) Map<String, bool> capabilities,
    @Default(<String, bool>{}) Map<String, bool> tools,
    int? freeSpaceBytes,
  }) = _DiagnosticsReport;

  /// Supported contract version range of this quickgui build.
  static const supportedContractVersion = 1;

  bool get contractCompatible =>
      contractVersion == null || contractVersion == supportedContractVersion;

  /// Plain-text report with the user's home directory replaced by `~`.
  String toSanitizedText({required String homeDirectory}) {
    String clean(String s) =>
        homeDirectory.isEmpty ? s : s.replaceAll(homeDirectory, '~');
    String mark(bool ok) => ok ? 'ok' : 'missing';
    final b = StringBuffer()
      ..writeln('Quickgui: $quickguiVersion')
      ..writeln('Backend available: $backendAvailable')
      ..writeln('Backend version: ${backendVersion ?? 'unknown'}')
      ..writeln('Contract version: ${contractVersion ?? 'none'}')
      ..writeln('KVM: ${mark(kvmAvailable)}')
      ..writeln('Working directory: ${clean(workingDirectory)}')
      ..writeln('Free space: ${freeSpaceBytes ?? 'unknown'} bytes')
      ..writeln('Tools:');
    for (final e in tools.entries) {
      b.writeln('  ${e.key}: ${mark(e.value)}');
    }
    b.writeln('Capabilities:');
    for (final e in capabilities.entries) {
      b.writeln('  ${e.key}: ${e.value}');
    }
    return b.toString();
  }
}
