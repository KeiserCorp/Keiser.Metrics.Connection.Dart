import 'dart:async';
import 'dart:io';

import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';
import 'package:test/test.dart';

/// Raw TCP listener that accepts a connection then destroys it without sending
/// any HTTP response. Both the REST probe and the WS upgrade fail with
/// "connection closed before full header was received" — the failure mode from
/// the field logs, where the websocket handshake itself never completes.
void main() {
  test(
    'a failing websocket handshake does not deadlock the reconnect loop',
    () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var accepts = 0;
      final sub = raw.listen((socket) {
        accepts++;
        socket.destroy();
      });

      final port = raw.port;
      final connection = MetricsConnection(
        restEndpoint: 'http://127.0.0.1:$port/api',
        socketEndpoint: 'ws://127.0.0.1:$port/ws',
      );

      // Let several reconnect cycles elapse.
      await Future.delayed(const Duration(seconds: 6));
      final acceptsAfter6s = accepts;

      await connection.dispose();
      await sub.cancel();
      await raw.close();

      // Pre-fix, `_closeSocket` awaited `sink.close()` on the never-established
      // channel, which hung forever — the socket retried exactly once and then
      // the loop was dead (accepts stuck at 1). The loop must keep cycling.
      expect(acceptsAfter6s, greaterThan(4),
          reason: 'reconnect loop must keep retrying after a handshake failure, '
              'not deadlock on the first attempt (accepts=$acceptsAfter6s)');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('reconnect loop stops once the connection is disposed', () async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var accepts = 0;
    final sub = raw.listen((socket) {
      accepts++;
      socket.destroy();
    });

    final port = raw.port;
    final connection = MetricsConnection(
      restEndpoint: 'http://127.0.0.1:$port/api',
      socketEndpoint: 'ws://127.0.0.1:$port/ws',
    );

    await Future.delayed(const Duration(seconds: 2));
    await connection.dispose();
    final acceptsAtDispose = accepts;

    // After dispose, no further connection attempts should be made.
    await Future.delayed(const Duration(seconds: 3));
    expect(accepts, acceptsAtDispose,
        reason: 'dispose must halt reconnect attempts');

    await sub.cancel();
    await raw.close();
  });
}
