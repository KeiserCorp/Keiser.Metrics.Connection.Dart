part of keiser_metrics_connection;

class MetricsApiError implements Exception {
  MetricsApiError({
    this.explanation,
    required this.code,
    required this.status,
    required this.name,
    required this.message,
    this.params,
  });

  String? explanation;
  int code;
  int status;
  String name;
  String message;
  List<String>? params;

  factory MetricsApiError.fromMap(Map<String, dynamic> json) => MetricsApiError(
        explanation: json["explanation"],
        code: json["code"],
        status: json["status"],
        name: json["name"],
        message: json["message"],
        params: _convertParamsToStringList(json["params"]),
      );

  Map<String, dynamic> toMap() => {
        "explanation": explanation,
        "code": code,
        "status": status,
        "name": name,
        "message": message,
        "params": params,
      };

    static List<String>? _convertParamsToStringList(dynamic params) {
    if (params is List<String>) {
      return params;
    } else if (params is List) {
      return params.map((e) => e.toString()).toList();
    } else if (params is String) {
      return [params];
    } else {
      return null;
    }
  }

  @override
  String toString() {
    return 'Error(code: $code, explanation: $explanation, status: $status,name: $name, message: $message, params: $params)';
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
