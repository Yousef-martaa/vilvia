/// A user profile attribute, deliberately unrelated to authorization
/// (`Profile.role`). Enum member names double as the backend's exact JSON
/// contract ("male"/"female"), so serialization is just `.name` / `.byName`
/// with no separate mapping to keep in sync.
enum Gender {
  male,
  female;

  String toJson() => name;

  /// Throws [ArgumentError] (via [EnumName.byName]) for anything other
  /// than a currently-known member name -- an unexpected value from the
  /// backend must fail loudly, not silently coerce to some default.
  static Gender fromJson(String value) => Gender.values.byName(value);
}

/// Authorization role, backed by the backend's `UserRole` enum
/// (`parent`/`admin`). Never derive this from anything other than a
/// verified `Profile` returned by `GET /me` -- there is no client-side
/// way to become `admin`.
enum UserRole {
  parent,
  admin;

  String toJson() => name;

  /// Throws [ArgumentError] for anything other than a currently-known
  /// member name -- an unexpected role from the backend must fail
  /// loudly, not silently be treated as `parent` (or worse, `admin`).
  static UserRole fromJson(String value) => UserRole.values.byName(value);
}

class Profile {
  final String id;
  final String firstName;
  final String email;
  final UserRole role;
  // Nullable: profiles created before this field existed have no value
  // and are not backfilled. New signups always set it -- see
  // docs/FEATURES/authentication.md.
  final Gender? gender;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    required this.firstName,
    required this.email,
    required this.role,
    this.gender,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      email: json['email'] as String,
      role: UserRole.fromJson(json['role'] as String),
      gender: json['gender'] == null
          ? null
          : Gender.fromJson(json['gender'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
