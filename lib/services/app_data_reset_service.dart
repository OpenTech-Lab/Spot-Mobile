import 'dart:async';

/// Broadcasts app-wide local-data reset events to active screens.
class AppDataResetService {
  AppDataResetService._();

  static final AppDataResetService instance = AppDataResetService._();

  final _localDataCleared = StreamController<void>.broadcast();

  Stream<void> get localDataCleared => _localDataCleared.stream;

  void notifyLocalDataCleared() {
    if (!_localDataCleared.isClosed) {
      _localDataCleared.add(null);
    }
  }
}
