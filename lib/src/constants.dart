part of keiser_metrics_connection;

const socketTimeout = Duration(seconds: 30);

enum ConnectionState { disconnected, connected }

enum ServerState { online, offline }

enum AuthenticationStatus { unauthenticated, authenticated, unknown }
