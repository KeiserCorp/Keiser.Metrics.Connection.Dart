part of keiser_metrics_connection;

SessionToken decodeJwt(String token) {
  return SessionToken.fromMap(JwtDecoder.decode(token));
}

enum TokenType {
  access,
  refresh,
}

class JWTToken {
  final String iss;
  final String jti;
  final int exp;
  final TokenType type;
  JWTToken({
    required this.iss,
    required this.jti,
    required this.exp,
    required this.type,
  });
}

SessionToken sessionTokenFromMap(String str) =>
    SessionToken.fromMap(jsonDecode(str));

String sessionTokenToMap(SessionToken data) => jsonEncode(data.toMap());

class SessionToken {
  SessionToken({
    required this.user,
    required this.facility,
    required this.facilityRole,
    required this.type,
    required this.iat,
    required this.exp,
    required this.iss,
    required this.jti,
  });

  final JWTUser user;
  final JWTFacility? facility;
  final String? facilityRole;
  final String type;
  final int iat;
  final int exp;
  final String iss;
  final String jti;

  factory SessionToken.fromMap(Map<String, dynamic> json) => SessionToken(
        user: JWTUser.fromMap(json['user']),
        facility: json.containsKey('facility')
            ? JWTFacility.fromMap(json['facility'])
            : null,
        facilityRole: json['facilityRole'],
        type: json['type'],
        iat: json['iat'],
        exp: json['exp'],
        iss: json['iss'],
        jti: json['jti'],
      );

  Map<String, dynamic> toMap() => {
        'user': user.toMap(),
        'facility': facility?.toMap(),
        'facilityRole': facilityRole,
        'type': type,
        'iat': iat,
        'exp': exp,
        'iss': iss,
        'jti': jti,
      };
}

class JWTFacility {
  JWTFacility({
    required this.id,
    required this.licensedUntil,
  });

  final int id;
  final DateTime licensedUntil;

  factory JWTFacility.fromMap(Map<String, dynamic> json) => JWTFacility(
        id: json['id'],
        licensedUntil: DateTime.parse(json['licensedUntil']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'licensedUntil': licensedUntil.toIso8601String(),
      };
}

class JWTUser {
  JWTUser({
    required this.id,
  });

  final int id;

  factory JWTUser.fromMap(Map<String, dynamic> json) => JWTUser(
        id: json['id'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
      };
}
