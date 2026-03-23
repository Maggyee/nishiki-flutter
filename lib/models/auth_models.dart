class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    this.emailVerifiedAt,
  });

  final String id;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? emailVerifiedAt;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: (json['id'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
      emailVerifiedAt: DateTime.tryParse(
        (json['emailVerifiedAt'] as String?) ?? '',
      ),
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final CurrentUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: (json['accessToken'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      user: CurrentUser.fromJson(
        (json['user'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
