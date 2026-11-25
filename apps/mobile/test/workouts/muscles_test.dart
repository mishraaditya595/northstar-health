import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/workouts/domain/muscles.dart';

void main() {
  group('validMuscles', () {
    test('accepts a valid pair and keeps the given order', () {
      final result = validMuscles(['hamstrings', 'glutes'], ['lowerBack']);
      expect(result, isNotNull);
      expect(result!.primary, ['hamstrings', 'glutes']);
      expect(result.secondary, ['lowerBack']);
    });

    test('accepts empty lists and primary only', () {
      expect(validMuscles(const [], const []), isNotNull);
      expect(validMuscles(['chest'], const []), isNotNull);
    });

    test('rejects each invalid rule', () {
      expect(validMuscles(['wings'], const []), isNull, reason: 'unknown');
      expect(validMuscles(['Chest'], const []), isNull, reason: 'case');
      expect(validMuscles(['chest', 'chest'], const []), isNull);
      expect(validMuscles(['chest'], ['lats', 'lats']), isNull);
      expect(validMuscles(['chest'], ['chest']), isNull, reason: 'overlap');
      expect(validMuscles(const [], ['chest']), isNull, reason: 'no primary');
      expect(
        validMuscles([...muscleVocabulary, 'chest'], const []),
        isNull,
        reason: '15 entries',
      );
    });
  });

  test('vocabulary has the 14 drawn muscle names', () {
    expect(muscleVocabulary.length, 14);
    expect(muscleVocabulary, Muscle.values.map((m) => m.name).toSet());
  });

  test('display names', () {
    expect(muscleDisplayName('lowerBack'), 'Lower back');
    expect(muscleDisplayName('chest'), 'Chest');
    expect(muscleDisplayName('hamstrings'), 'Hamstrings');
  });

  test('every vocabulary name maps to a Muscle', () {
    for (final name in muscleVocabulary) {
      expect(muscleFromName(name)?.name, name);
    }
    expect(muscleFromName('wings'), isNull);
  });
}
