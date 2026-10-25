/// Typed error returned by application use cases so the presentation
/// layer receives structured failures instead of raw exit codes.
class Failure {
  const Failure(this.code, this.message, {this.detail});

  final String code;
  final String message;
  final String? detail;
}
