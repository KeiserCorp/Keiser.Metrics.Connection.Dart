import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
import 'package:test/test.dart';

/// Completes the WS handshake then immediately drops the socket, simulating a
/// server that is reachable at the TCP/HTTP layer but cannot hold a session.
class _FlapServer {
  _FlapServer(this._server) {
    _server.listen(_handle);
  }

  static Future<_FlapServer> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FlapServer(s);
  }

  final HttpServer _server;
  final List<DateTime> connectTimes = [];

  int get port => _server.port;
  String get restEndpoint => 'http://127.0.0.1:$port/api';
  String get socketEndpoint => 'ws://127.0.0.1:$port/ws';

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/ws') {
      connectTimes.add(DateTime.now());
      final ws = await WebSocketTransformer.upgrade(request);
      await ws.close();
      return;
    }
    // Status probes from the reconnect path; keep them cheap.
    await request.drain<void>();
    request.response.write(jsonEncode({'name': 'fake'}));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  test(
    'reconnect backoff climbs against a server that drops every handshake',
    () async {
      final server = await _FlapServer.start();
      final connection = MetricsConnection(
        restEndpoint: server.restEndpoint,
        socketEndpoint: server.socketEndpoint,
      );

      // Long enough to cross the tier-10 boundary in nextReconnectDelay, where
      // the per-attempt delay first grows past the 1s floor.
      await Future.delayed(const Duration(seconds: 16));
      await connection.dispose();
      await server.close();

      final times = server.connectTimes;
      expect(times.length, greaterThan(3),
          reason: 'the client must keep retrying, not give up');

      final gaps = <int>[
        for (var i = 1; i < times.length; i++)
          times[i].difference(times[i - 1]).inMilliseconds,
      ];

      // The bug: a successful handshake reset _socketRetryAttempts to 0 every
      // cycle, pinning every gap at the ~1s floor. With the fix the counter
      // climbs (handshake alone no longer counts as stable), so once attempts
      // pass tier 10 the delay grows past the floor.
      final maxGap = gaps.fold<int>(0, (m, g) => g > m ? g : m);
      expect(maxGap, greaterThan(1700),
          reason: 'backoff must grow beyond the 1s floor under a flapping '
              'server; gaps observed: $gaps');

      // And it must not hammer the server at ~1/sec for the whole window.
      expect(times.length, lessThan(16),
          reason: 'too many attempts implies the backoff never engaged');
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
