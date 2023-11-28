# keiser_metrics_connection

The purpose of this package is to provide a convenient way to **connect** to the Keiser Metrics server. It does not provide any interface representing the routes/models of the server.

If you are looking for our SDK which contains convenience functions & models mapped to all of our server routes, please refer to [keiser_metrics_sdk](https://pub.dev).

> NOTE - This package is a dependency of `keiser_metrics_sdk`

## Features

- **Websocket**
  - Primary method of communication with server.
- **REST**
  - HTTP Fallback (if websocket is not enabled).
- **Request Queue**
  - Will start queueing requests after a certain amount within a short time period.
- **Request Retry**
  - Will automatically retry failed requests a certain number of times.
- **Keep Alive**
  - Will automatically make `keep-alive` requests when authenticated
- **Event Based**
  - Exposes several streams for you to keep track of the following:
    - websocket connection status
    - server status
    - authentication status

## Getting started

Install:

```bash
flutter pub add keiser_metrics_connection
```

Import:

```dart
import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
```

## Usage

```dart
final connection = MetricsConnection(
    shouldEnableWebSocket, // default: true
    socketTimeout, // default: 30 seconds
    concurrentRequestLimit, // default: 5
    requestRetryLimit, // default: 5
    shouldEnableErrorLogging, // default: false
);

// Listen for state changes
connection.onConnectionStatusChange.listen(event => {/* websocket connected || websocket disconnected */});
connection.onServerStatusChange.listen(event => {/* server online || server offline */});
connection.onAuthenticationStatusChange.listen(event => {/* authenticated || unauthenticated || unknown */});
connection.onRefreshTokenChange.listen(event => {/* new refresh token */});

// You  must call this method before making a request to any authenticated routes.
// You can obtain a refresh token by signing in via our website.
await connection.initializeAuthenticatedSession(token: myRefreshToken);

// Use the `action` method to make requests to desired routes.
final response = await connection.action(/* route, params */);

// Dispose of the instance when you are done with it.
connection.dispose();
```

## Additional information

### Errors

```dart
class MetricsApiError implements Exception {

  // ...

  String? explanation;
  int code; // internal api codes
  int status; // standard server status codes (e.g. 200, 500, etc)
  String name; // e.g. "TokenInvalid", "UnauthorizedResource"
  String message;

 // ...

}
```

### State Events

```dart
enum ConnectionState { disconnected, connected } // websocket

enum ServerState { online, offline }

enum AuthenticationState { unauthenticated, authenticated, unknown }
```
