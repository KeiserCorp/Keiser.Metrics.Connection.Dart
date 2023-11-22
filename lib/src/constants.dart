part of keiser_metrics_connection;

enum ConnectionState { disconnected, connected }

enum ServerState { online, offline }

enum AuthenticationStatus { unauthenticated, authenticated, unknown }

const defaultRestEndpoint = 'https://metrics-api.keiser.com/api';
const defaultSocketEndpoint = 'wss://metrics-api.keiser.com/ws';
const defaultShouldEnableWebSocket = true;
const defaultSocketTimeout = Duration(seconds: 30);
const defaultConcurrentRequestLimit = 5;
const defaultRequestRetryLimit = 5;
