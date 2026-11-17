import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:cardiograph/core/time/measurement_time.dart';
import 'package:cardiograph/core/validation/measurement_validation.dart';
import 'package:cardiograph/features/measurements/measurement.dart';

void main() {
  setUpAll(data.initializeTimeZones);
  test('Confini al secondo e tutti i 1440 minuti', () {
    const cases = {
      '06:59:59': DayBand.evening,
      '07:00:00': DayBand.morning,
      '13:00:00': DayBand.morning,
      '13:00:59': DayBand.morning,
      '13:01:00': DayBand.afternoon,
      '19:00:59': DayBand.afternoon,
      '19:01:00': DayBand.evening,
      '23:59:59': DayBand.evening,
      '00:00:00': DayBand.evening,
    };
    for (final entry in cases.entries) {
      expect(bandFor(DateTime.parse('2026-11-14T${entry.key}Z')), entry.value);
    }
    final counts = <DayBand, int>{};
    for (var minute = 0; minute < 1440; minute++) {
      final band = bandFor(DateTime.utc(2026, 11, 14, 0, minute));
      counts[band] = (counts[band] ?? 0) + 1;
    }
    expect(counts, {
      DayBand.morning: 361,
      DayBand.afternoon: 360,
      DayBand.evening: 719,
    });
  });
  test(
    'Data civile e sera notturna restano distinte anche su anno/bisestile',
    () {
      final night = DateTime.utc(2026, 1, 1, 2, 30, 59);
      expect(dateKey(night), '2026-01-01');
      expect(anchorDate(night), '2025-12-31');
      expect(anchorDate(DateTime.utc(2024, 3, 1, 6, 59)), '2024-02-29');
      expect(anchorDate(DateTime.utc(2026, 1, 1, 7)), '2026-01-01');
      expect(
        CivilPeriod('2026-01-01', '2026-01-01').contains(dateKey(night)),
        isTrue,
      );
    },
  );
  test('Soglie strettamente maggiori, indipendenti', () {
    expect([129, 130, 131].map(systolicHigh), [false, true, true]);
    expect([84, 85, 86].map(diastolicHigh), [false, true, true]);
    expect([99, 100, 101].map(pulseHigh), [false, true, true]);
    expect(systolicHigh(135.01), isTrue);
  });
  test('Interi positivi obbligatori, senza segni o decimali', () {
    for (final value in ['', '0', '-1', '+1', '1.5', '1000', ' 123', '12a']) {
      expect(numberError(value), isNotNull);
    }
    for (final value in ['1', '123', '999']) {
      expect(numberError(value), isNull);
    }
  });
  test('DST Roma: gap rifiutato, fold con due istanti e offset distinti', () {
    expect(
      resolveWall(DateTime.utc(2026, 3, 29, 2, 30), 'Europe/Rome'),
      isEmpty,
    );
    final fold = resolveWall(DateTime.utc(2026, 10, 25, 2, 30), 'Europe/Rome');
    expect(fold.length, 2);
    expect(fold.map((v) => v.timeZoneOffset.inMinutes), [120, 60]);
    expect(fold.last.difference(fold.first), const Duration(hours: 1));
    expect(
      resolveWall(DateTime.utc(2026, 3, 29, 3, 30), 'Europe/Rome').length,
      1,
    );
  });
  test('Statistiche vuote senza zeri inventati e media non arrotondata', () {
    final empty = MeasurementStats([]);
    expect(empty.count, 0);
    expect(empty.systolic.mean, isNull);
    expect(empty.pulse.minimum, isNull);
    final metric = MetricStats([135, 136]);
    expect(metric.mean, 135.5);
    expect(metric.minimum, 135);
    expect(metric.maximum, 136);
  });
  test('ID UUID v4 distinto per ogni bozza', () {
    final ids = List.generate(100, (_) => newMeasurementId());
    expect(ids.toSet().length, 100);
    for (final id in ids) {
      expect(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id),
        isTrue,
      );
    }
  });
  test('Date storiche non dipendono dal fuso globale corrente', () {
    final instant = DateTime.utc(2026, 11, 14, 23, 30, 15);
    final local = instant.add(const Duration(hours: 1));
    final m = Measurement(
      id: 'sample',
      systolic: 123,
      diastolic: 88,
      pulse: 64,
      measuredAtUtc: instant,
      zone: 'Europe/Rome',
      offsetMinutes: 60,
      localDate: dateKey(local),
      localTime: timeKey(local),
      createdAtUtc: instant,
      updatedAtUtc: instant,
    );
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    expect(m.localDate, '2026-11-15');
    expect(m.localTime, '00:30:15');
    expect(m.periodAnchorDate, '2026-11-14');
    m.validate();
    tz.setLocalLocation(tz.UTC);
  });
}
