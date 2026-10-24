import '../../domain/common/result.dart';

/// Maps backend stderr/exit codes to typed [Failure] codes.
Failure mapBackendError(int exitCode, String stderr) {
  final m = stderr.toLowerCase();
  if (m.contains('not found')) {
    return Failure('backend.not_found', stderr.trim());
  }
  if (m.contains('error!')) {
    return Failure('backend.error', stderr.trim());
  }
  return Failure('backend.exit_$exitCode', stderr.trim());
}
