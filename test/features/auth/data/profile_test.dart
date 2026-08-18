import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/auth/data/profile.dart';

Map<String, dynamic> _json({Object? gender = 'male'}) => {
      'id': 'user-1',
      'first_name': 'Rowan',
      'email': 'parent@example.com',
      'role': 'parent',
      'gender': gender,
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

  group('Profile.fromJson', () {
    test('parses a known gender value', () {
      final profile = Profile.fromJson(_json(gender: 'female'));
      expect(profile.gender, Gender.female);
    });

    test('parses a null gender as null (legacy profile)', () {
      final profile = Profile.fromJson(_json(gender: null));
      expect(profile.gender, isNull);
    });

    test('throws clearly for an unexpected gender value from the backend',
        () {
      expect(() => Profile.fromJson(_json(gender: 'nonbinary')),
          throwsArgumentError);
    });
  });
}
