import 'package:quickgui/core/errors/failure.dart';

/// Minimal Result type used by application use cases so the
/// presentation layer receives typed errors instead of raw exit codes.
/// [Failure] lives in `core/errors/failure.dart`.

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
