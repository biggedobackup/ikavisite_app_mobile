import 'dart:async';

class CancelToken {
  bool _isCancelled = false;
  final List<Completer> _awaiters = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    for (final completer in _awaiters) {
      if (!completer.isCompleted) {
        completer.completeError(CancelledException());
      }
    }
    _awaiters.clear();
  }

  Future<void> get cancelled {
    if (_isCancelled) return Future.error(CancelledException());
    final completer = Completer<void>();
    _awaiters.add(completer);
    return completer.future;
  }

  void throwIfCancelled() {
    if (_isCancelled) throw CancelledException();
  }
}

class CancelledException implements Exception {
  @override
  String toString() => 'Requête annulée';
}
