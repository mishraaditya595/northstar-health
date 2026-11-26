import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

TrainingProgramRecord program(int firstDayWeekday) => TrainingProgramRecord(
  uuid: 'p',
  name: 'P',
  description: '',
  sourceId: 'prog.x',
  sourceRelease: 4,
  firstDayWeekday: firstDayWeekday,
  isActive: true,
  updatedAtMs: 0,
  days: [
    for (var i = 0; i < 7; i++)
      ProgramDayRecord(
        uuid: 'd$i',
        dayIndex: i,
        planUuid: i.isEven ? 'plan$i' : null,
      ),
  ],
);

void main() {
  // 2026-11-23 is a Monday, 2026-11-29 a Sunday.
  final monday = DateTime(2026, 11, 23);
  final sunday = DateTime(2026, 11, 29);

  group('programDayIndex', () {
    test('every first weekday against a Monday and a Sunday', () {
      final expectedMonday = {1: 0, 2: 6, 3: 5, 4: 4, 5: 3, 6: 2, 7: 1};
      final expectedSunday = {1: 6, 2: 5, 3: 4, 4: 3, 5: 2, 6: 1, 7: 0};
      for (var first = 1; first <= 7; first++) {
        expect(programDayIndex(monday, first), expectedMonday[first]);
        expect(programDayIndex(sunday, first), expectedSunday[first]);
      }
    });
  });

  test('localDateKey pads month and day', () {
    expect(localDateKey(DateTime(2026, 3, 4, 23, 50)), '2026-03-04');
    expect(localDateKey(DateTime(2026, 11, 25)), '2026-11-25');
  });

  test('dayFor picks the day by weekday', () {
    final p = program(3); // day 0 is Wednesday
    expect(dayFor(p, DateTime(2026, 11, 25)).dayIndex, 0);
    expect(dayFor(p, monday).dayIndex, 5);
    expect(dayFor(p, DateTime(2026, 11, 25, 23, 59)).uuid, 'd0');
  });

  test('calendarWeek wraps past Sunday', () {
    final week = calendarWeek(program(6)); // Saturday first
    expect(week.map((e) => e.weekday), [6, 7, 1, 2, 3, 4, 5]);
    expect(week.map((e) => e.day.dayIndex), [0, 1, 2, 3, 4, 5, 6]);
    for (var first = 1; first <= 7; first++) {
      expect(calendarWeek(program(first)).first.weekday, first);
    }
  });
}
