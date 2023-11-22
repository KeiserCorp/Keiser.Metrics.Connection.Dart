import 'dart:async';

import 'package:keiser_metrics_connection/keiser_metrics_connection.dart';

const defaultRequestTimeout = 15000;
const jwtTTLLimit = 5000;
final pingRegex = RegExp("^primus::ping::(\\d{13})\$");

class RequestHandler {
  final Completer<ResponseMessage> completer;
  final String path;
  final String action;
  final bool shouldRetry;
  final Map<String, dynamic> params;
  final Map<String, dynamic> socketParams;
  final Map<String, dynamic>? bodyParams;
  final String method;

  RequestHandler({
    required this.completer,
    required this.path,
    required this.action,
    required this.shouldRetry,
    required this.params,
    required this.socketParams,
    required this.bodyParams,
    required this.method,
  });
}

class SocketPushMessage {
  final context = 'user';
  int from;
  Object message;
  String room;
  int sentAt;

  SocketPushMessage({
    required this.from,
    required this.message,
    required this.room,
    required this.sentAt,
  });
}

abstract class ConnectionHandler {
  ConnectionHandler({
    required String restEndpoint,
    required String socketEndpoint,
  }) : metricsConnection = MetricsConnection(
          restEndpoint: restEndpoint,
          socketEndpoint: socketEndpoint,
        );
  final MetricsConnection metricsConnection;
}
