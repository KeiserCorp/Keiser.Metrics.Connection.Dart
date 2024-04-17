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
  final context = WebsocketMessageContext.response;
  Object? data;
  int? messageId;
  Object? error;

  ResponseMessage({
    this.data,
    this.messageId,
    this.error,
  });

  factory ResponseMessage.fromMap(Map<String, dynamic> map) {
    return ResponseMessage(
      data: map,
      messageId: map['messageId'],
      error: map['error'],
    );
  }

  @override
  String toString() =>
      'ResponseMessage(data: $data, messageId: $messageId, error: $error)';
}

class ChatRoomMessage {
  final context = WebsocketMessageContext.user;
  final dynamic data;
  final String room;
  final int from;
  final DateTime sentAt;

  ChatRoomMessage({
    required this.data,
    required this.room,
    required this.from,
    required this.sentAt,
  });

  factory ChatRoomMessage.fromMap(Map<String, dynamic> map) {
    return ChatRoomMessage(
      data: map['message'],
      room: map['room'] as String,
      from: int.tryParse(map['from']) ?? 0,
      sentAt: DateTime.fromMillisecondsSinceEpoch(map['sentAt'] as int),
    );
  }

  @override
  String toString() {
    return 'ChatRoomMessage(data: $data, room: $room, from: $from, sentAt: $sentAt)';
  }
}
