/// Minimal Result/Failure types used by application use cases so the
/// presentation layer receives typed errors instead of raw exit codes.
class Failure {
  const Failure(this.code, this.message, {this.detail});

  final String code;
  final String message;
  final String? detail;
}

sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
