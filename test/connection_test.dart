import 'dart:async';

import 'package:dotenv/dotenv.dart';
import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
import 'package:test/test.dart';

class _Server {
  _Server({
    required this.domain,
    required this.isSecure,
    required this.email,
    required this.password,
  });

  final String domain;
  final bool isSecure;
  final String email;
  final String password;

  String get restEndpoint => '${isSecure ? 'https' : 'http'}://$domain/api';
  String get socketEndpoint => '${isSecure ? 'wss' : 'ws'}://$domain/ws';
}

void main() {
  const isProduction =
      String.fromEnvironment('ENV', defaultValue: 'DEV') == 'PROD';
  final List<_Server> servers = [];
  MetricsConnection? connection;

  ConnectionState connectionState = ConnectionState.disconnected;
  ServerState serverState = ServerState.offline;
  AuthenticationState authenticationState = AuthenticationState.unknown;

  StreamSubscription<ConnectionState>? connectionStateSubscription;
  StreamSubscription<ServerState>? serverStateSubscription;
  StreamSubscription<AuthenticationState>? authenticationStateSubscription;

  final env = DotEnv()..load([isProduction ? '.env.prod' : '.env.dev']);
  servers.add(
    _Server(
      domain: env['SERVER_DOMAIN_1']!,
      isSecure: isProduction,
      email: env['SERVER_EMAIL_1']!,
      password: env['SERVER_PASSWORD_1']!,
    ),
  );

  if (!isProduction) {
    servers.add(
      _Server(
        domain: env['SERVER_DOMAIN_2']!,
        isSecure: false,
        email: env['SERVER_EMAIL_2']!,
        password: env['SERVER_PASSWORD_2']!,
      ),
    );
  }

  Future<void> _openConnection(_Server server) async {
    connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      requestRetryLimit: 1,
      socketTimeout: const Duration(seconds: isProduction ? 30 : 5),
    );

    connectionStateSubscription =
        connection!.onConnectionStatusChange.listen((event) {
      connectionState = event;
    });
    serverStateSubscription = connection!.onServerStatusChange.listen((event) {
      serverState = event;
    });
    authenticationStateSubscription =
        connection!.onAuthenticationStatusChange.listen((event) {
      authenticationState = event;
    });
  }

  Future<void> _resetTestState() async {
    await connectionStateSubscription?.cancel();
    await serverStateSubscription?.cancel();
    await authenticationStateSubscription?.cancel();
    await connection?.dispose();
    connection = null;
    connectionStateSubscription = null;
    serverStateSubscription = null;
    authenticationStateSubscription = null;
    connectionState = ConnectionState.disconnected;
    serverState = ServerState.offline;
    authenticationState = AuthenticationState.unknown;
  }

  for (final server in servers) {
    group('Target Server: ${server.domain}', () {
      test('Can open metrics connection', () async {
        await _openConnection(server);

        await Future.delayed(const Duration(seconds: 6));
        expect(connectionState, ConnectionState.connected);
        expect(serverState, ServerState.online);
        expect(authenticationState, AuthenticationState.unknown);
      });

      test('Can dispose and re-open metrics connection', () async {
        await _resetTestState();
        await _openConnection(server);

        await Future.delayed(const Duration(seconds: 6));
        expect(connectionState, ConnectionState.connected);
        expect(serverState, ServerState.online);
        expect(authenticationState, AuthenticationState.unknown);
      });

      test('Can make unauthenticated request', () async {
        final res = await connection!
            .action(path: '/status', action: 'core:status', method: 'GET');
        final data = res.data! as Map<String, dynamic>;
        expect(data, isNotNull);
        expect(data['uptime'], isNotNull);
        await Future.delayed(const Duration(seconds: 1));
        expect(authenticationState, AuthenticationState.unknown);
      });

      test('Cannot make authenticated request when unauthenticated', () async {
        final res = connection!
            .action(path: '/user/show', action: 'user:show', method: 'GET');

        await expectLater(res,
            throwsA(predicate((e) => e is MetricsApiError && e.code == 613)));

        await Future.delayed(const Duration(seconds: 1));
        expect(authenticationState, AuthenticationState.unauthenticated);
      });

      test('Can authenticate via auth:login', () async {
        final params = {
          'email': server.email,
          'password': server.password,
          'refreshable': true
        };
        final res = await connection!.action(
          path: '/auth/login',
          action: 'auth:login',
          method: 'POST',
          queryParameters: params,
        );

        final data = res.data! as Map<String, dynamic>;
        expect(data, isNotNull);
        expect(data['accessToken'], isNotNull);
        expect(data['refreshToken'], isNotNull);
        await Future.delayed(const Duration(seconds: 1));
        expect(authenticationState, AuthenticationState.authenticated);
      });

      test('Can make unauthenticated request when authenticated', () async {
        final res = await connection!
            .action(path: '/status', action: 'core:status', method: 'GET');
        final data = res.data! as Map<String, dynamic>;
        expect(data, isNotNull);
        expect(data['uptime'], isNotNull);
        await Future.delayed(const Duration(seconds: 1));
        expect(authenticationState, AuthenticationState.authenticated);
      });

      test('Can make authenticated request when authenticated', () async {
        final res = await connection!
            .action(path: '/user/show', action: 'user:show', method: 'GET');

        final data = res.data! as Map<String, dynamic>;
        expect(data, isNotNull);
        expect(data['accessToken'], isNotNull);
        expect(data['user'], isNotNull);
        await Future.delayed(const Duration(seconds: 1));
        expect(authenticationState, AuthenticationState.authenticated);
      });

      test('Can close Metrics Connection', () async {
        connection!.close();

        await Future.delayed(const Duration(seconds: 5));
        expect(connectionState, ConnectionState.disconnected);
        expect(serverState, ServerState.offline);
        expect(authenticationState, AuthenticationState.unknown);
      });

      test('Cannot make request when instance is closed', () async {
        final res = connection!
            .action(path: '/status', action: 'core:status', method: 'GET');

        await expectLater(res, throwsA(predicate((e) => e is UnexpectedError)));
      });

      tearDownAll(() async {
        await _resetTestState();
      });
    });
  }
}
