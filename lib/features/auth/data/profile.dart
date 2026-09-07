/// A user profile attribute, deliberately unrelated to authorization
/// (`Profile.role`). Enum member names double as the backend's exact JSON
/// contract ("male"/"female"), so serialization is just `.name` / `.byName`
/// with no separate mapping to keep in sync.
enum Gender {
  male,
  female;

  String toJson() => name;

  static Gender fromJson(String value) => Gender.values.byName(value);
}

enum ParentRole {
  mother,
  father,
  guardian,
  preferNotToSay;

  String toJson() => switch (this) {
        mother => 'mother',
        father => 'father',
        guardian => 'guardian',
        preferNotToSay => 'prefer_not_to_say',
      };

  static ParentRole fromJson(String value) => switch (value) {
        'mother' => mother,
        'father' => father,
        'guardian' => guardian,
        'prefer_not_to_say' => preferNotToSay,
        _ => throw ArgumentError.value(value, 'value', 'Unknown parent role'),
      };

  String get label => switch (this) {
        mother => 'Mother',
        father => 'Father',
        guardian => 'Guardian',
        preferNotToSay => 'Prefer not to say',
      };
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
  final String? lastName;
  final String email;
  final UserRole role;
  // Nullable: profiles created before this field existed have no value
  // and are not backfilled.
  final Gender? gender;
  final ParentRole? parentRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    required this.firstName,
    this.lastName,
    required this.email,
    required this.role,
    this.gender,
    this.parentRole,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String?,
      email: json['email'] as String,
      role: UserRole.fromJson(json['role'] as String),
      gender: json['gender'] == null
          ? null
          : Gender.fromJson(json['gender'] as String),
      parentRole: json['parent_role'] == null
          ? null
          : ParentRole.fromJson(json['parent_role'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
