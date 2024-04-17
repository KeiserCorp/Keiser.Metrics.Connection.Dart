part of keiser_metrics_connection;

JWTToken decodeJwt(String token) {
  final jwtToken = JwtDecoder.decode(token);
  if (jwtToken.containsKey('role') && jwtToken['role'] == 'machine') {
    return MachineSessionToken.fromMap(jwtToken);
  }
  return SessionToken.fromMap(jwtToken);
}

enum TokenType {
  access,
  refresh,
  machine,
}

class JWTToken {
  final String iss;
  final String jti;
  final int? exp;
  final TokenType type;
  JWTToken({
    required this.iss,
    required this.jti,
    required this.type,
    this.exp,
  });
}

SessionToken sessionTokenFromMap(String str) =>
    SessionToken.fromMap(jsonDecode(str));

String sessionTokenToMap(SessionToken data) => jsonEncode(data.toMap());

class SessionToken extends JWTToken {
  SessionToken({
    required this.user,
    required this.facility,
    required this.facilityRole,
    required super.type,
    required this.iat,
    required int exp,
    required super.iss,
    required super.jti,
  }) : super(exp: exp);

  final JWTUser user;
  final JWTFacility? facility;
  final String? facilityRole;
  final int iat;

  factory SessionToken.fromMap(Map<String, dynamic> json) => SessionToken(
        user: JWTUser.fromMap(json['user']),
        facility: json.containsKey('facility')
            ? JWTFacility.fromMap(json['facility'])
            : null,
        facilityRole: json['facilityRole'],
        type: EnumToString.fromString(TokenType.values, json['type'])!,
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

class JWTMachine extends JWTUser {
  JWTMachine({required super.id});

  factory JWTMachine.fromMap(Map<String, dynamic> json) => JWTMachine(
        id: json['id'],
      );
}

class MachineSessionToken extends JWTToken {
  final JWTMachine machine;
  final String role;

  MachineSessionToken(
      {required super.iss,
      required super.jti,
      required super.type,
      required this.machine,
      required this.role});

  factory MachineSessionToken.fromMap(Map<String, dynamic> json) =>
      MachineSessionToken(
        iss: json['iss'],
        jti: json['jti'],
        type: EnumToString.fromString(TokenType.values, json['type'])!,
        machine: JWTMachine.fromMap(json['machine']),
        role: json['role'],
      );
}
