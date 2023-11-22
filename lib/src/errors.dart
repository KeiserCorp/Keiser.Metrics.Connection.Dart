part of keiser_metrics_connection;

class MetricsApiError implements Exception {
  MetricsApiError({
    this.explanation,
    required this.code,
    required this.status,
    required this.name,
    required this.message,
  });

  String? explanation;
  int code;
  int status;
  String name;
  String message;

  factory MetricsApiError.fromMap(Map<String, dynamic> json) => MetricsApiError(
        explanation: json["explanation"],
        code: json["code"],
        status: json["status"],
        name: json["name"],
        message: json["message"],
      );

  Map<String, dynamic> toMap() => {
        "explanation": explanation,
        "code": code,
        "status": status,
        "name": name,
        "message": message,
      };

  @override
  String toString() {
    return 'Error(code: $code, explanation: $explanation, status: $status,name: $name, message: $message)';
  }
}

class UnexpectedError extends MetricsApiError {
  UnexpectedError({required String message})
      : super(
            code: -1, status: 500, name: 'Unexpected Error', message: message);

  @override
  String toString() {
    return 'UnexpectedError(name: $name, message: $message)';
  }
}
