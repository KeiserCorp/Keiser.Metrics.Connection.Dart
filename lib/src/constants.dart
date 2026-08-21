part of '../keiser_metrics_connection.dart';

enum WebsocketMessageContext { response, user }

enum ConnectionState { disconnected, connected }

enum ServerState { online, offline }

enum AuthenticationState { unauthenticated, authenticated, unknown }

const defaultRestEndpoint = 'https://metrics-api.keiser.com/api';
const defaultSocketEndpoint = 'wss://metrics-api.keiser.com/ws';
const defaultShouldEnableWebSocket = true;
const defaultSocketConnectionTimeout = Duration(seconds: 30);
const defaultSocketMessageTimeout = Duration(seconds: 45);
const defaultConcurrentRequestLimit = 5;
const defaultRequestRetryLimit = 5;

/// How long before access-token expiration the keep-alive renewal fires.
const defaultKeepAliveRenewalBuffer = Duration(seconds: 5);

/// How long a websocket must stay connected before its successful connection
/// clears the reconnect backoff. Guards against a server that accepts the
/// handshake then immediately drops resetting the backoff every cycle.
const _socketStabilityWindow = Duration(seconds: 10);
