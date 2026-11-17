import 'package:cardiograph/features/measurements/diary.dart';
import 'package:cardiograph/core/design_system/range_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cardiograph/core/health_ranges.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/features/analytics/pressure_pie.dart';
import 'package:cardiograph/features/analytics/analytics_model.dart';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/app/providers.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'analytics_calendar_test.dart' show reading, TestClock;

void main() {
  setUpAll(tz.initializeTimeZones);
  test('Confini sistolica/diastolica e precedenza completa dei casi misti', () {
    for (final (value, expected) in [
      (89, PressureRange.low),
      (90, PressureRange.normal),
      (129, PressureRange.normal),
      (130, PressureRange.grade1),
      (139, PressureRange.grade1),
      (140, PressureRange.grade2),
      (159, PressureRange.grade2),
      (160, PressureRange.grade3),
    ]) {
      expect(systolicRange(value), expected);
    }
    for (final (value, expected) in [
      (59, PressureRange.low),
      (60, PressureRange.normal),
      (84, PressureRange.normal),
      (85, PressureRange.grade1),
      (89, PressureRange.grade1),
      (90, PressureRange.grade2),
      (99, PressureRange.grade2),
      (100, PressureRange.grade3),
    ]) {
      expect(diastolicRange(value), expected);
    }
    expect(pressureRange(145, 78), PressureRange.grade2);
    expect(pressureRange(85, 92), PressureRange.grade2);
    expect(pressureRange(85, 100), PressureRange.grade3);
    expect(pressureRange(130, 55), PressureRange.grade1);
    expect(pressureRange(110, 55), PressureRange.low);
    expect(systolicRange(129.999), PressureRange.normal);
    expect(diastolicRange(84.999), PressureRange.normal);
    for (final sys in [1, 89, 90, 129, 130, 139, 140, 159, 160, 999]) {
      for (final dia in [1, 59, 60, 84, 85, 89, 90, 99, 100, 999]) {
        final priority = [
          systolicRange(sys).priority,
          diastolicRange(dia).priority,
        ].reduce((a, b) => a > b ? a : b);
        expect(pressureRange(sys, dia).priority, priority);
      }
    }
  });
  test('Pulsazioni: 59 blu, 60/99 verde, 100 rosso; colori esatti', () {
    expect(pulseRange(59), PulseRange.low);
    expect(pulseRange(60), PulseRange.normal);
    expect(pulseRange(99), PulseRange.normal);
    expect(pulseRange(100), PulseRange.high);
    expect(PressureRange.values.map((r) => r.hex), [
      0xff3b82f6,
      0xff10b981,
      0xfff59e0b,
      0xfff97316,
      0xffef4444,
    ]);
    expect(PulseRange.values.map((r) => r.hex), [
      0xff3b82f6,
      0xff10b981,
      0xffef4444,
    ]);
    expect(Metric.pulse.rangeHex(100), 0xffef4444);
    // Colored calendar counts use a dark backing, other text stays navy.
    for (final r in PressureRange.values) {
      expect(
        (Color(r.hex).computeLuminance() + .05) /
            (const Color(0xff071627).computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
  test('Distribuzione percentuali dai dati originali; zeri e vuoto', () {
    final d = PressureDistribution([
      PressureRange.normal,
      PressureRange.normal,
      PressureRange.low,
    ]);
    expect(d.counts[PressureRange.normal], 2);
    expect(d.percent(PressureRange.normal), closeTo(200 / 3, 1e-10));
    expect(d.percent(PressureRange.grade3), 0);
    expect(
      PressureRange.values.map(d.percent).reduce((a, b) => a + b),
      closeTo(100, 1e-10),
    );
    expect(PressureDistribution([]).percent(PressureRange.normal), 0);
  });
  test('Calendario: priorità SQL coerente al dominio, anche misti', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = MeasurementRepository(db);
    for (final (i, sys, dia) in [
      (1, 110, 70),
      (2, 85, 55),
      (3, 135, 80),
      (4, 85, 92),
      (5, 165, 70),
    ]) {
      await repo.save(
        reading(
          '$i',
          DateTime.utc(2024, 2, i, 12),
          sys: sys,
          dia: dia,
          pulse: 80,
        ),
      );
    }
    final month = await repo.monthSummary('2024-02');
    expect(
      month.values.map((d) => d.category).toSet(),
      PressureRange.values.toSet(),
    );
    await repo.save(
      reading(
        'low-mixed',
        DateTime.utc(2024, 2, 1, 13),
        sys: 80,
        dia: 55,
        pulse: 80,
      ),
    );
    await repo.save(
      reading(
        'high-mixed',
        DateTime.utc(2024, 2, 1, 14),
        sys: 145,
        dia: 78,
        pulse: 80,
      ),
    );
    expect(
      (await repo.monthSummary('2024-02'))['2024-02-01']!.category,
      PressureRange.grade2,
    );
    await repo.close();
    await db.close();
  });
  testWidgets('Letture: colori per metrica senza badge o spiegazioni', (
    t,
  ) async {
    final m = reading(
      'colors',
      DateTime.utc(2024, 2, 29, 12),
      sys: 135,
      dia: 92,
      pulse: 100,
    );
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(body: ReadingCard(m)),
      ),
    );
    expect(
      t.widget<Text>(find.text('135')).style!.color,
      const Color(0xfff59e0b),
    );
    expect(
      t.widget<Text>(find.text('92')).style!.color,
      const Color(0xfff97316),
    );
    expect(
      t.widget<Text>(find.text('100')).style!.color,
      const Color(0xffef4444),
    );
    expect(find.byType(RangeBadge), findsNothing);
    expect(find.textContaining('Ipertensione'), findsNothing);
  });
  testWidgets('Torta: fette 0% omesse, conteggi leggibili e stato vuoto', (
    t,
  ) async {
    final row = reading(
      'normal',
      DateTime.utc(2024, 2, 29, 12),
      sys: 110,
      dia: 70,
      pulse: 80,
    );
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(body: SingleChildScrollView(child: PressurePie([row]))),
      ),
    );
    await t.pumpAndSettle();
    expect(t.widget<PieChart>(find.byType(PieChart)).data.sections.length, 1);
    expect(
      t.widget<PieChart>(find.byType(PieChart)).data.sections.single.title,
      '100.0%',
    );
    expect(find.text(pressureLegend), findsNothing);
    expect(find.text(pulseLegend), findsNothing);
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: const Scaffold(
          body: SingleChildScrollView(child: PressurePie([])),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(PieChart), findsNothing);
    expect(find.text('Nessuna misurazione nel periodo'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Torta Andamento usa gli stessi filtri di periodo e fascia', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = MeasurementRepository(db);
    await repo.save(
      reading(
        'recent',
        DateTime.utc(2024, 2, 29, 12),
        sys: 145,
        dia: 70,
        pulse: 80,
      ),
    );
    await repo.save(
      reading(
        'evening',
        DateTime.utc(2024, 2, 28, 20),
        sys: 110,
        dia: 70,
        pulse: 80,
      ),
    );
    await repo.save(
      reading(
        'old',
        DateTime.utc(2020, 1, 1, 12),
        sys: 165,
        dia: 70,
        pulse: 80,
      ),
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          measurementRepositoryProvider.overrideWith((ref) async => repo),
          clockProvider.overrideWithValue(TestClock()),
        ],
        child: const CardioGraphApp(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Andamento').last);
    await t.pumpAndSettle();
    expect(t.widget<PressurePie>(find.byType(PressurePie)).rows.length, 2);
    await t.tap(find.text('Tutte le misurazioni'));
    await t.pumpAndSettle();
    expect(t.widget<PressurePie>(find.byType(PressurePie)).rows.length, 3);
    await t.tap(find.text('Sera'));
    await t.pumpAndSettle();
    expect(
      t.widget<PressurePie>(find.byType(PressurePie)).rows.single.id,
      'evening',
    );
    await t.pumpWidget(const SizedBox());
    await repo.close();
    await db.close();
  });
}
