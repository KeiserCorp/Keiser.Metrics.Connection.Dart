import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
import 'package:test/test.dart';

/// Builds an unsigned JWT whose payload decodes to a [MachineSessionToken]
/// (role == 'machine'). That token type carries no `exp`, so `_updateTokens`
/// skips the keep-alive timer — exactly what these token-plumbing tests want.
String _machineJwt(String jti) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'none', 'typ': 'JWT'});
  final body = seg({
    'role': 'machine',
    'type': 'machine',
    'iss': 'fake',
    'jti': jti,
    'machine': {'id': 1},
  });
  return '$header.$body.sig';
}

/// In-process HTTP/WS server for queue + auth tests. REST-only (socket disabled
/// by the tests), so `/ws` is unused here.
class _FakeServer {
  _FakeServer(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeServer(server);
  }

  final HttpServer _server;

  // /api/concurrent bookkeeping.
  int _activeConcurrent = 0;
  int maxConcurrent = 0;
  int concurrentHits = 0;

  // /api/protected auth bookkeeping.
  final String accessTokenA = _machineJwt('access-a');
  final String accessTokenB = _machineJwt('access-b');
  String refreshToken = 'refresh-1';
  String? _validAccessToken; // null => the seeded access token is "expired".
  int refreshUses = 0;
  int protectedSuccesses = 0;

  int get port => _server.port;
  String get restEndpoint => 'http://127.0.0.1:$port/api';
  String get socketEndpoint => 'ws://127.0.0.1:$port/ws';

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    res.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/api/concurrent':
        await request.drain<void>();
        concurrentHits++;
        _activeConcurrent++;
        if (_activeConcurrent > maxConcurrent) {
          maxConcurrent = _activeConcurrent;
        }
        // Hold the request open so overlapping requests actually coexist.
        await Future.delayed(const Duration(milliseconds: 50));
        _activeConcurrent--;
        res.write(jsonEncode({'ok': true}));
        await res.close();
        break;

      case '/api/signin':
        await request.drain<void>();
        res.write(jsonEncode({
          'accessToken': accessTokenA,
          'refreshToken': refreshToken,
        }));
        await res.close();
        break;

      case '/api/protected':
        await request.drain<void>();
        final auth = request.uri.queryParameters['authorization'];
        if (auth == refreshToken) {
          // Refresh exchange: issue a brand-new access token and mark it valid.
          refreshUses++;
          _validAccessToken = accessTokenB;
          refreshToken = 'refresh-2';
          res.write(jsonEncode({
            'accessToken': accessTokenB,
            'refreshToken': refreshToken,
            'ok': true,
          }));
          await res.close();
        } else if (auth != null && auth == _validAccessToken) {
          protectedSuccesses++;
          res.write(jsonEncode({'ok': true}));
          await res.close();
        } else {
          // Expired / invalid access token -> 616.
          res.statusCode = 400;
          res.write(jsonEncode({
            'error': {
              'code': 616,
              'status': 400,
              'name': 'InvalidToken',
              'message': 'invalid token',
            },
          }));
          await res.close();
        }
        break;

      default:
        res.statusCode = 404;
        await res.close();
    }
  }

  Future<void> close() => _server.close(force: true);
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
      'queued requests beyond the concurrency limit all complete and never '
      'exceed the limit', () async {
    final connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      shouldEnableWebSocket: false,
      concurrentRequestLimit: 2,
      requestRetryLimit: 1,
    );

    // Fire far more than the limit. Pre-fix, the queue drained one item per
    // active completion and stalled once the active set hit zero, so this
    // Future.wait would hang. It must now resolve every request.
    final futures = List.generate(
      10,
      (_) => connection.action(
        path: '/concurrent',
        action: 'test:concurrent',
        method: 'GET',
      ),
    );

    final responses = await Future.wait(futures).timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('queue stalled: not all requests completed'),
    );

    expect(responses, hasLength(10));
    expect(server.concurrentHits, 10,
        reason: 'every queued request must reach the server');
    expect(server.maxConcurrent, lessThanOrEqualTo(2),
        reason: 'concurrency limit must be enforced for queued items too');
    expect(server.maxConcurrent, greaterThan(1),
        reason: 'requests should actually run concurrently up to the limit');

    await connection.dispose();
  });

  test(
      'concurrent 616s trigger a single token refresh and all requests then '
      'succeed', () async {
    final connection = MetricsConnection(
      restEndpoint: server.restEndpoint,
      socketEndpoint: server.socketEndpoint,
      shouldEnableWebSocket: false,
      concurrentRequestLimit: 10,
      requestRetryLimit: 1,
    );

    // Seed access + refresh tokens via a sign-in response.
    await connection.action(
      path: '/signin',
      action: 'auth:signin',
      method: 'GET',
    );

    // Five requests fire together. Each gets a 616 on the (expired) access
    // token. Only the first may spend the refresh token; the rest must wait
    // for that refresh and retry with the freshly issued access token.
    final futures = List.generate(
      5,
      (_) => connection.action(
        path: '/protected',
        action: 'test:protected',
        method: 'GET',
      ),
    );

    final responses = await Future.wait(futures).timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('refresh race deadlocked'),
    );

    expect(responses, hasLength(5));
    expect(
      responses.every((r) => (r.data as Map<String, dynamic>)['ok'] == true),
      isTrue,
      reason: 'every request must ultimately succeed after the refresh',
    );
    expect(server.refreshUses, 1,
        reason: 'the refresh token must be spent exactly once, not per-request');
    // The single refresher is served by the refresh-exchange response itself;
    // the other four wait on it and retry against the protected route with the
    // new access token.
    expect(server.protectedSuccesses, 4,
        reason: 'the non-refresher requests must retry with the new token');

    await connection.dispose();
  });
}
