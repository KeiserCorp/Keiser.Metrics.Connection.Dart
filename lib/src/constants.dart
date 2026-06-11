part of keiser_metrics_connection;

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
