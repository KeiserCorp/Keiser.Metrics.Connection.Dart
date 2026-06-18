part of '../keiser_metrics_connection.dart';

final _maxReconnectDelay = Duration(minutes: 5);
final _random = Random();

int _cloudReconnectDelayMs(int attempt) {
  if (attempt < 10) {
    return 1000;
  }
  if (attempt < 20) {
    return 2000;
  }
  final tierIndex = ((attempt - 20) ~/ 5).clamp(0, 16);
  final delayMs = 4000 * (1 << tierIndex);
  return delayMs.clamp(4000, _maxReconnectDelay.inMilliseconds);
}

Duration nextReconnectDelay(int reconnectAttempts) {
  final capped = _cloudReconnectDelayMs(reconnectAttempts);
  final jittered = capped * (0.8 + _random.nextDouble() * 0.4);
  return Duration(milliseconds: jittered.round());
}
