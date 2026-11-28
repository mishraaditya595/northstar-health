import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/widgets/energy_text.dart';
import 'package:flutter_test/flutter_test.dart';

Energy _energy(int value, int start) => Energy(
  value: value,
  band: readinessBandOf(value),
  start: start,
  items: const [],
);

void main() {
  _watchReasonTests();
  group('energyChangeText', () {
    test('down since morning', () {
      expect(
        energyChangeText(_energy(62, 78)),
        'Started today at 78 · down 16 since morning',
      );
    });

    test('no change since morning', () {
      expect(
        energyChangeText(_energy(78, 78)),
        'Started today at 78 · no change since morning',
      );
    });

    test('never writes a negative number if above the start', () {
      expect(
        energyChangeText(_energy(80, 78)),
        'Started today at 78 · up 2 since morning',
      );
    });
  });

  group('energyLearningText', () {
    test('workouts only, with singular', () {
      expect(
        energyLearningText(const EnergyLearning(workoutsNeeded: 12)),
        'Still learning your patterns: 12 more workouts for a calibrated '
        'score.',
      );
      expect(
        energyLearningText(const EnergyLearning(workoutsNeeded: 1)),
        'Still learning your patterns: 1 more workout for a calibrated score.',
      );
    });

    test('days only, with singular', () {
      expect(
        energyLearningText(const EnergyLearning(daysNeeded: 9)),
        'Still learning your patterns: 9 more days of data for a calibrated '
        'score.',
      );
      expect(
        energyLearningText(const EnergyLearning(daysNeeded: 1)),
        'Still learning your patterns: 1 more day of data for a calibrated '
        'score.',
      );
    });

    test('both', () {
      expect(
        energyLearningText(
          const EnergyLearning(workoutsNeeded: 12, daysNeeded: 9),
        ),
        'Still learning your patterns: 12 more workouts and 9 more days of '
        'data for a calibrated score.',
      );
    });

    test('null when not shown', () {
      expect(energyLearningText(const EnergyLearning()), isNull);
      expect(
        energyLearningText(const EnergyLearning(workoutsNeeded: 0)),
        isNull,
      );
    });
  });

  group('energyItemLabel', () {
    test('workout and nap use the local time', () {
      expect(
        energyItemLabel(
          EnergyItem(
            kind: EnergyItemKind.workout,
            points: -9,
            at: DateTime(2026, 11, 24, 7, 10),
          ),
        ),
        'Workout at 7:10 AM',
      );
      expect(
        energyItemLabel(
          EnergyItem(
            kind: EnergyItemKind.nap,
            points: 3,
            at: DateTime(2026, 11, 24, 14, 40),
          ),
        ),
        'Nap at 2:40 PM',
      );
      expect(
        energyItemLabel(
          EnergyItem(
            kind: EnergyItemKind.nap,
            points: 3,
            at: DateTime(2026, 11, 24, 14, 40),
            capped: true,
          ),
        ),
        'Nap at 2:40 PM (capped)',
      );
    });

    test('active day and awake hours', () {
      expect(
        energyItemLabel(
          const EnergyItem(kind: EnergyItemKind.activeDay, points: -4),
        ),
        'Active day so far',
      );
      expect(
        energyItemLabel(
          const EnergyItem(
            kind: EnergyItemKind.awake,
            points: -1,
            awakeHours: 1,
          ),
        ),
        'Awake 1 hour',
      );
      expect(
        energyItemLabel(
          const EnergyItem(
            kind: EnergyItemKind.awake,
            points: -1,
            awakeHours: 10,
          ),
        ),
        'Awake 10 hours',
      );
    });
  });

  test('energyPointsText uses a real minus sign', () {
    expect(energyPointsText(-9), '−9');
    expect(energyPointsText(3), '+3');
  });

  test('energyBuildingText', () {
    expect(energyBuildingText(1), 'Energy starts after 1 more day with data.');
    expect(energyBuildingText(2), 'Energy starts after 2 more days with data.');
    expect(energyBuildingText(1), contains('1 more day with'));
  });
}

void _watchReasonTests() {
  group('energyWatchReason', () {
    test('down, no change and up since morning', () {
      expect(
        energyWatchReason(_energy(62, 78), const EnergyLearning()),
        'Started at 78 · down 16 since morning',
      );
      expect(
        energyWatchReason(_energy(78, 78), const EnergyLearning()),
        'Started at 78 · no change since morning',
      );
      expect(
        energyWatchReason(_energy(81, 78), const EnergyLearning()),
        'Started at 78 · up 3 since morning',
      );
    });

    test('adds still learning while learning shows', () {
      expect(
        energyWatchReason(
          _energy(62, 78),
          const EnergyLearning(workoutsNeeded: 3),
        ),
        'Started at 78 · down 16 since morning · still learning',
      );
    });
  });
}
