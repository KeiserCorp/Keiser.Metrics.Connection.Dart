import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';

void main() {
  final connection = MetricsConnection();

// Listen for state changes
connection.onConnectionStatusChange.listen(event => {/* websocket connected || websocket disconnected */});
connection.onServerStatusChange.listen(event => {/* server online || server offline */});
connection.onAuthenticationStatusChange.listen(event => {/* authenticated || unauthenticated || unknown */});
connection.onRefreshTokenChange.listen(event => {/* new refresh token */});

// You  must call this method before making a request to any authenticated routes.
// You can obtain a refresh token by signing in via our website.
await connection.initializeAuthenticatedSession(token: myRefreshToken);

// Use the `action` method to make requests to desired routes.
final response = await connection.action(path: '/user', method: 'user:show', method: 'GET');

// Dispose of the instance when you are done with it.
await connection.dispose();
}
