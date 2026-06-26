## 2.0.0

**Breaking changes**

* Removes the public `open()` method; the connection now opens automatically from the constructor, so callers should no longer call `connection.open()`
* Removes the `socketRetryTimeout` parameter in favor of the new exponential backoff

**New features**

* Replaces the fixed retry-timeout ladder with jittered exponential backoff for socket and REST reconnects (1 second floor, capped at 5 minutes)
* Gates the backoff reset behind a stability window so a server that accepts the handshake then immediately drops is backed off instead of hammered at the floor
* Adds `connectionReconnectDelay` to override the computed backoff with a fixed delay for both socket and REST reconnection attempts
* Switches the websocket to `IOWebSocketChannel` with a native 30 second ping interval and built-in connect timeout

**Bug fixes**

* Routes socket errors through teardown so awaiters receive an error instead of hanging when the connection drops
* Coordinates concurrent `616` token-refresh responses through a shared refresh completer so the refresh token is spent once and other requests retry with the new access token
* Adds an `_isRestRetrying` single-flight guard so concurrent connection errors no longer spawn competing REST retry loops that race the backoff counter and tear down each other's Dio
* Fixes the request queue stalling with budget free and items still waiting
* Guards `_checkIfAuthenticated` against non-map payloads
* Cancels all lifecycle timers and resets backoff counters on `close()`
* Guards state emits against closed controllers and dedupes them so consumers stop receiving duplicate events
* Guards socket reopen against a connection closed during the retry delay

**Maintenance**

* Switches the analyzer config from `flutter_lints` to `package:lints/recommended.yaml` to match this pure-Dart package
* Removes the manual `connection.open()` call from the example

## 1.1.0

* Keeps server online when a REST request fails with a connection error but the websocket is still connected, avoiding unnecessary reconnect and re-auth cycles
* Rebuilds the REST client lazily for body requests when Dio is unavailable but the socket is still connected
* Drains pending requests on disconnect so callers receive an error immediately instead of hanging indefinitely
* Fixes race condition in websocket message ID tracking
* Adds per-message socket timeout via `socketMessageTimeout` (default 45 seconds); renames `defaultSocketTimeout` to `defaultSocketConnectionTimeout`
* Automatically closes the connection when server status transitions to offline
* Fixes multipart upload retries by cloning `MultipartFile` values before each attempt

## 1.0.1

* Sets server status to online on successful request

## 1.0.0

* Adds support for new server tokens

## 0.7.4

* Improves error handling by ensuring both null and type checks are performed before accessing 'error' in the response data. This prevents potential runtime exceptions when handling API errors. (Issue [#19](https://github.com/KeiserCorp/Keiser.Metrics.Connection.Dart/issues/19))
* Fixes reconnect errors after internet is lost (Issue [#17](https://github.com/KeiserCorp/Keiser.Metrics.Connection.Dart/issues/17))

## 0.7.3

* Fixes missing error exception type `connectionError`

## 0.7.2

* Fixes issue related to Dio update

## 0.7.1

* Fixes issue related to Dio update

## 0.7.0

* Updates Dio dependency to v5.7.0

## 0.6.0

* Updates error model to include `params` field.

## 0.5.0

* Adds method to clear authentication state `clearAuthentication`.

## 0.4.1

* Fixes invalid or expired tokens from being used again.

## 0.4.0

* Adds the parameter to override the default socket connection retry timeout.

## 0.3.1

* Fixes chat room message parsing

## 0.3.0

* Adds Machine JWT implementation

## 0.2.2

* Fixes settings sever status to offline after an HTTP request.

## 0.2.1

* Fixes authenticated state when an blacklisted token error is triggered.

## 0.2.0

* Adds `onChatRoomMessage` stream to listen for any "live" chat room messages.

## 0.1.0

* Initial Release
