part of keiser_metrics_connection;

AuthenticatedResponse authenticatedResponseFromMap(String str) =>
    AuthenticatedResponse.fromMap(json.decode(str));

String authenticatedResponseToMap(AuthenticatedResponse data) =>
    json.encode(data.toMap());
