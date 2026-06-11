import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
import 'package:test/test.dart';

/// In-process HTTP/WS server simulating the Metrics backend, so these tests
/// run without a live server (unlike keiser_metrics_connection_test.dart).
class _FakeServer {
  _FakeServer(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeServer(server);
  }

  final HttpServer _server;
  final List<WebSocket> _webSockets = [];

  int flakyAttempts = 0;
  final List<int> flakyBodyLengths = [];

  int get port => _server.port;
  String get restEndpoint => 'http://127.0.0.1:$port/api';
  String get socketEndpoint => 'ws://127.0.0.1:$port/ws';

  Future<void> _handle(HttpRequest request) async {
    switch (request.uri.path) {
      case '/ws':
        final ws = await WebSocketTransformer.upgrade(request);
        _webSockets.add(ws);
        // Any non-response/non-user JSON map flips the client's
        // ConnectionState to connected (see _onSocketMessage).
        ws.add(jsonEncode({'context': 'connect'}));
        ws.listen((_) {});
        break;
      case '/api/status':
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'name': 'fake'}));
        await request.response.close();
        break;
      case '/api/kill':
        // Abruptly destroy the TCP connection mid-request so the client
        // surfaces a connection-class DioException.
        await request.drain<void>();
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.destroy();
        break;
      case '/api/flaky':
        flakyAttempts++;
        final length = await request
            .fold<int>(0, (total, chunk) => total + chunk.length);
        flakyBodyLengths.add(length);
        request.response.headers.contentType = ContentType.json;
        if (flakyAttempts == 1) {
          request.response.statusCode = 500;
          request.response.write(jsonEncode({'message': 'transient'}));
        } else {
          request.response.write(jsonEncode({'ok': true}));
        }
        await request.response.close();
        break;
      default:
        request.response.statusCode = 404;
        await request.response.close();
    }
  }

  Future<void> close() async {
    for (final ws in _webSockets) {
      await ws.close();
    }
    await _server.close(force: true);
  }
}

Future<void> _waitForSocketConnected(MetricsConnection connection) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!connection.isSocketConnected) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Websocket never connected to fake server');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _FakeServer server;

  setUp(() async {
    server = await _FakeServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  test(
      'REST connection failure with healthy websocket does not flip server '
      'offline or close the socket', () async {
    final connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      requestRetryLimit: 1,
    );
    final offlineEvents = <ServerState>[];
    final sub = connection.onServerStatusChange.listen(offlineEvents.add);

    await _waitForSocketConnected(connection);
    expect(connection.serverStatus, ServerState.online);

    // Body parameters force the request over REST even though the socket is
    // connected; the server destroys the TCP connection mid-request.
    await expectLater(
      connection.action(
        path: '/kill',
        action: 'test:kill',
        method: 'POST',
        bodyParameters: {'foo': 'bar'},
      ),
      throwsA(isA<UnexpectedError>()),
    );

    expect(connection.serverStatus, ServerState.online,
        reason: 'one failed REST request must not declare the server offline');
    expect(connection.isSocketConnected, isTrue,
        reason: 'the healthy websocket must survive a REST request failure');
    expect(offlineEvents, isNot(contains(ServerState.offline)));

    await sub.cancel();
    await connection.dispose();
  });

  test(
      'REST connection failure without a websocket still flips server '
      'offline', () async {
    final connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      shouldEnableWebSocket: false,
      requestRetryLimit: 1,
    );

    // Prime server status to online via a successful REST call.
    await connection.action(
      path: '/status',
      action: 'core:status',
      method: 'GET',
    );
    expect(connection.serverStatus, ServerState.online);

    await expectLater(
      connection.action(
        path: '/kill',
        action: 'test:kill',
        method: 'POST',
        bodyParameters: {'foo': 'bar'},
      ),
      throwsA(isA<UnexpectedError>()),
    );

    expect(connection.serverStatus, ServerState.offline,
        reason: 'with no socket to vouch for the server, a REST '
            'connection failure still means offline');

    await connection.dispose();
  });

  test('multipart body survives a retry attempt', () async {
    final connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      shouldEnableWebSocket: false,
      requestRetryLimit: 3,
    );

    final response = await connection.action(
      path: '/flaky',
      action: 'test:flaky',
      method: 'POST',
      bodyParameters: {
        'workoutSetData': MultipartFile.fromBytes(
          List<int>.filled(1024, 7),
          filename: 'set.gz',
        ),
      },
    );

    expect(server.flakyAttempts, 2,
        reason: 'first attempt 500s, retry must succeed');
    expect(server.flakyBodyLengths.every((length) => length > 1024), isTrue,
        reason: 'both attempts must carry the full multipart body');
    expect((response.data as Map<String, dynamic>)['ok'], isTrue);

    await connection.dispose();
  });
}
