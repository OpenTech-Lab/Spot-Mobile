class SingleFlight<T> {
  Future<T>? _inFlight;

  Future<T> run(Future<T> Function() action) {
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = action();
    _inFlight = future;
    future.then<void>(
      (_) {
        if (identical(_inFlight, future)) {
          _inFlight = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlight, future)) {
          _inFlight = null;
        }
      },
    );
    return future;
  }
}
