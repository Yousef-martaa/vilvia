import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/auth/data/profile.dart';

Map<String, dynamic> _json({
  Object? gender = 'male',
  Object? parentRole = 'mother',
  Object? role = 'parent',
}) =>
    {
      'id': 'user-1',
      'first_name': 'Rowan',
      'last_name': 'Smith',
      'email': 'parent@example.com',
      'role': role,
      'gender': gender,
      'parent_role': parentRole,
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-01T00:00:00Z',
    };

void main() {
  group('Gender', () {
    test('toJson serializes to the exact backend contract value', () {
      expect(Gender.male.toJson(), 'male');
      expect(Gender.female.toJson(), 'female');
    });

    test('fromJson parses a known value', () {
      expect(Gender.fromJson('male'), Gender.male);
      expect(Gender.fromJson('female'), Gender.female);
    });

    test('fromJson throws clearly for an unexpected value instead of '
        'silently mapping to something else', () {
      expect(() => Gender.fromJson('nonbinary'), throwsArgumentError);
    });
  });

  group('ParentRole', () {
    test('toJson serializes to the exact backend contract value', () {
      expect(ParentRole.mother.toJson(), 'mother');
      expect(ParentRole.father.toJson(), 'father');
      expect(ParentRole.guardian.toJson(), 'guardian');
      expect(ParentRole.preferNotToSay.toJson(), 'prefer_not_to_say');
    });

    test('fromJson parses a known value', () {
      expect(ParentRole.fromJson('mother'), ParentRole.mother);
      expect(
          ParentRole.fromJson('prefer_not_to_say'), ParentRole.preferNotToSay);
    });

    test('fromJson throws clearly for an unexpected value', () {
      expect(() => ParentRole.fromJson('cousin'), throwsArgumentError);
    });
  });

  group('UserRole', () {
    test('toJson serializes to the exact backend contract value', () {
      expect(UserRole.parent.toJson(), 'parent');
      expect(UserRole.admin.toJson(), 'admin');
    });

    test('fromJson parses a known value', () {
      expect(UserRole.fromJson('parent'), UserRole.parent);
      expect(UserRole.fromJson('admin'), UserRole.admin);
    });

    test('fromJson throws clearly for an unexpected value instead of '
        'silently mapping to parent or admin', () {
      expect(() => UserRole.fromJson('superadmin'), throwsArgumentError);
    });
  });

  group('Profile.fromJson', () {
    test('parses full profile info', () {
      final profile = Profile.fromJson(_json(
        parentRole: 'mother',
      ));
      expect(profile.firstName, 'Rowan');
      expect(profile.lastName, 'Smith');
      expect(profile.parentRole, ParentRole.mother);
    });

    test('parses a known gender value', () {
      final profile = Profile.fromJson(_json(gender: 'female'));
      expect(profile.gender, Gender.female);
    });

    test('parses null gender and parentRole as null (legacy profile)', () {
      final profile = Profile.fromJson(_json(gender: null, parentRole: null));
      expect(profile.gender, isNull);
      expect(profile.parentRole, isNull);
    });

    test('throws clearly for an unexpected gender value from the backend',
        () {
      expect(() => Profile.fromJson(_json(gender: 'nonbinary')),
          throwsArgumentError);
    });

    test('parses a known role value as UserRole', () {
      final profile = Profile.fromJson(_json(role: 'admin'));
      expect(profile.role, UserRole.admin);
    });

    test('throws clearly for an unexpected role value from the backend', () {
      expect(() => Profile.fromJson(_json(role: 'superadmin')),
          throwsArgumentError);
    });
  });
}
