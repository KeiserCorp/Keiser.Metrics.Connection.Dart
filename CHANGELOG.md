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
