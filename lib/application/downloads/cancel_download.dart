import '../../domain/common/result.dart';

/// Use case: cancel an in-flight download.
class CancelDownload {
  CancelDownload(this._cancel);
  final Future<Result<void>> Function() _cancel;

  Future<Result<void>> call() => _cancel();
}
