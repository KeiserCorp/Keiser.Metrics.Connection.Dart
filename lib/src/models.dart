part of keiser_metrics_connection;

class ConnectionStateEvent {
  final ConnectionState connectionState;
  ConnectionStateEvent({
    required this.connectionState,
  });
}

class RefreshTokenChangeEvent {
  final String refreshToken;

  RefreshTokenChangeEvent({
    required this.refreshToken,
  });
}

class AuthenticatedResponse {
  AuthenticatedResponse({
    required this.accessToken,
    this.refreshToken,
  });

  final String? refreshToken;
  final String accessToken;

  factory AuthenticatedResponse.fromMap(Map<String, dynamic> json) =>
      AuthenticatedResponse(
        refreshToken: json["refreshToken"],
        accessToken: json["accessToken"],
      );

  Map<String, dynamic> toMap() => {
        "refreshToken": refreshToken,
        "accessToken": accessToken,
      };
}

class ResponseMessage {
  final context = 'response';
  Object? data;
  int? messageId;
  Object? error;

  ResponseMessage({
    this.data,
    this.messageId,
    this.error,
  });

  factory ResponseMessage.fromMap(Map<String, dynamic> json) {
    return ResponseMessage(
      data: json,
      messageId: json['messageId'],
      error: json['error'],
    );
  }

  @override
  String toString() =>
      'ResponseMessage(data: $data, messageId: $messageId, error: $error)';
}
