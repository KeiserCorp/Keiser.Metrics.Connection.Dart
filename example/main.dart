import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';

bool _isAuthenticated = false;
bool _isConnected = false;
bool _isServerOnline = false;

void main() {
  final connection = MetricsConnection(
    restEndpoint: 'http://192.168.208.191:8080/api',
    socketEndpoint: 'ws://192.168.208.191:8080/ws',
    requestRetryLimit: 1,
    socketTimeout: Duration(seconds: 5),
  );

  connection.onServerStatusChange.listen((event) {
    _isServerOnline = event == ServerState.online;
    _printStatus();
  });
  connection.onConnectionStatusChange.listen((event) {
    _isConnected = event == ConnectionState.connected;
    _printStatus();
  });
  connection.onAuthenticationStatusChange.listen((event) {
    _isAuthenticated = event == AuthenticationState.authenticated;
    _printStatus();
  });

  connection.open();
}

void _printStatus() {
  print(_StatusEvent(
    isAuthenticated: _isAuthenticated,
    isConnected: _isConnected,
    isOnline: _isServerOnline,
  ));
}

class _StatusEvent {
  _StatusEvent({
    required this.isAuthenticated,
    required this.isConnected,
    required this.isOnline,
  });

  final bool isAuthenticated;
  final bool isConnected;
  final bool isOnline;

  @override
  String toString() =>
      '_StatusEvent(isAuthenticated: $isAuthenticated, isConnected: $isConnected, isOnline: $isOnline)';
}
