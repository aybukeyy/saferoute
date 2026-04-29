// Sealed Result<T, E> type for error-as-value handling across services.
//
// Used by ReportsRepository, SyncService, RoutingService for surfacing
// recoverable failures (rate limit, classification timeout, location denied)
// without throwing. Production code paths must `switch` on the sealed
// hierarchy and handle both arms — the analyzer enforces exhaustiveness.

sealed class Result<T, E> {
  const Result();

  /// Returns the wrapped success value, or `null` for [Err].
  T? get valueOrNull => switch (this) {
        Ok<T, E>(value: final v) => v,
        Err<T, E>() => null,
      };

  /// Returns the wrapped error, or `null` for [Ok].
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(error: final e) => e,
      };

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  /// Maps the success value through [f]; passes the error through unchanged.
  Result<R, E> map<R>(R Function(T) f) => switch (this) {
        Ok<T, E>(value: final v) => Ok<R, E>(f(v)),
        Err<T, E>(error: final e) => Err<R, E>(e),
      };

  /// Maps the error through [f]; passes the success value through unchanged.
  Result<T, F> mapErr<F>(F Function(E) f) => switch (this) {
        Ok<T, E>(value: final v) => Ok<T, F>(v),
        Err<T, E>(error: final e) => Err<T, F>(f(e)),
      };
}

final class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);

  @override
  String toString() => 'Err($error)';
}
