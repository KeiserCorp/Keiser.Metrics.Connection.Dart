# keiser_metrics_connection

The purpose of this package is to provide a convenient way to **connect** to the Keiser Metrics server.

If you are looking for our SDK which contains convenience functions & models mapped to all of our server routes, please refer to [keiser_metrics_sdk](https://pub.dev).

> NOTE - This package is a dependency of `keiser_metrics_sdk`

## Features

- **Websocket**
  - Primary method of communication with server.
- **REST**
  - Fallback (if websocket is not enabled).
- **Request Queue**
  - Will start queueing requests after a certain amount within a short time period.
- **Retry**
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

This package comes with **two** different main classes you can instantiate. Choose the one that fits your needs.

#### Metrics Connection

Use this if you only intend to make requests to `unauthenticated` routes. All constructor params are optional.

```dart
final connection = MetricsConnection(
    shouldEnableWebSocket, // default: true
    socketTimeout, // default: 30 seconds
    concurrentRequestLimit, // default: 5
    requestRetryLimit, // default: 5
);

connection.onConnectionChange.listen(event => {/* Do something */});
connection.onServerStatusChange.listen(event => {/* Do something */});

final response = await connection.action(path: '/status', action: 'core:status', method: r'GET');
```

#### Authenticated Metrics Connection

Use this if you only intend to make requests to `authenticated` routes. All constructor params are optional.

```dart
final authenticatedConnection = AuthenticatedMetricsConnection(
    shouldEnableWebSocket, // default: true
    socketTimeout, // default: 30 seconds
    concurrentRequestLimit, // default: 5
    requestRetryLimit, // default: 5
);

authenticatedConnection.metricsConnection.onConnectionChange.listen(event => {/* Do something */});
authenticatedConnection.metricsConnection.onServerStatusChange.listen(event => {/* Do something */});
authenticatedConnection.metricsConnection.onAuthenticationStatusChanged.listen(event => {/* Do something */});
authenticatedConnection.onRefreshToken.listen(event => {/* Store new refresh token */});


await authenticatedConnection.initializeAuthenticatedSession(token: myRefreshToken);

// Any time you make an authenticated request, make sure you call `updateTokens` after you receive a response.
final response = await authenticatedConnection.action(/* Authenticated Route */);
final authenticatedResponse =
          AuthenticatedResponse.fromMap(response.data! as Map<String, dynamic>);
authenticatedConnection.updateTokens(authenticatedResponse);
```

> NOTE: You must sign in via our website to obtain a refresh token.

## Additional information

#### Errors

```dart
class MetricsApiError implements Exception {

  // ...

  String? explanation;
  int code; // internal api codes
  int status; // standard server status codes
  String name; // e.g. "TokenInvalid", "UnauthorizedResource"
  String message;

 // ...

}
```

#### State

```dart
enum ConnectionState { disconnected, connected }

enum ServerState { online, offline }

enum AuthenticationStatus { unauthenticated, authenticated, unknown }
```
