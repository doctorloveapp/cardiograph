import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:image/image.dart' as im;
import 'package:fl_chart/fl_chart.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/app/providers.dart';
import 'package:cardiograph/core/services/contracts.dart';
import 'package:cardiograph/core/services/photo_services.dart';
import 'package:cardiograph/core/vision/seven_segment.dart';
import 'package:cardiograph/core/vision/camera_guide.dart';
import 'package:cardiograph/core/time/measurement_time.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/calendar_summary.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/features/measurements/measurement.dart';
import 'package:cardiograph/features/analytics/analytics_model.dart';
import 'package:cardiograph/features/analytics/analytics_page.dart';

Measurement reading(
  String id,
  DateTime wall, {
  int sys = 135,
  int dia = 90,
  int pulse = 100,
  int revision = 0,
}) {
  final utc = wall.subtract(const Duration(hours: 1));
  return Measurement(
    id: id,
    systolic: sys,
    diastolic: dia,
    pulse: pulse,
    measuredAtUtc: utc,
    zone: 'Europe/Rome',
    offsetMinutes: 60,
    localDate: dateKey(wall),
    localTime: timeKey(wall),
    createdAtUtc: utc,
    updatedAtUtc: utc,
    revision: revision,
  );
}

class TestClock implements AppClock {
  @override
  DateTime now() => DateTime.utc(2024, 2, 29, 12);
}

class CountingRepo extends MeasurementRepository {
  int monthQueries = 0, dayQueries = 0;
  CountingRepo(super.db);
  @override
  Future<Map<String, CalendarDaySummary>> monthSummary(String month) {
    monthQueries++;
    return super.monthSummary(month);
  }

  @override
  Future<List<Measurement>> list({CivilPeriod? period}) {
    if (period != null && period.start == period.end) dayQueries++;
    return super.list(period: period);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);
  testWidgets('Andamento reale al 200%: due pannelli, statistiche e filtri', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = MeasurementRepository(db);
    await repo.save(reading('normal', DateTime.utc(2024, 2, 29, 12)));
    await repo.save(
      reading(
        'high',
        DateTime.utc(2024, 2, 28, 6),
        sys: 136,
        dia: 91,
        pulse: 101,
      ),
    );
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
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
    expect(find.text('2 letture · 2 giorni con dati'), findsOneWidget);
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.textContaining('Oltre soglia'), findsNothing);
    await t.ensureVisible(find.text('90 giorni'));
    await t.pumpAndSettle();
    await t.tap(find.text('90 giorni'));
    await t.pumpAndSettle();
    expect(find.textContaining('Aggregazione giornaliera:'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await repo.close();
    await db.close();
  });
  test(
    'Archivio esteso: aggregazione SQL di 10.000 letture e picchi giornalieri',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = MeasurementRepository(db);
      try {
        await db.customSelect('SELECT 1').get();
        await db.batch((batch) {
          for (var i = 0; i < 10000; i++) {
            final m = reading(
              '$i',
              DateTime.utc(2024, 2, 1 + i % 29, i % 24),
              sys: 134 + i % 5,
            );
            batch.customStatement(
              'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
              m.values.values.toList(),
            );
          }
        });
        final timer = Stopwatch()..start();
        final month = await repo.monthSummary('2024-02');
        timer.stop();
        expect(month.values.fold<int>(0, (n, d) => n + d.count), 10000);
        expect(month.length, 29);
        final data = AnalyticsData(
          await repo.list(period: CivilPeriod('2024-02-01', '2024-02-29')),
          period: CivilPeriod('2024-02-01', '2024-02-29'),
        );
        expect(data.stats.count, 10000);
        expect(data.observations.length, 29);
        expect(data.stats.systolic.maximum, 138);
        // ignore: avoid_print
        print(
          'Query mensile aggregata 10.000 letture: ${timer.elapsedMilliseconds} ms (SQLite test locale)',
        );
      } finally {
        await repo.close();
        await db.close();
      }
    },
  );
  test('Cornice -30% centrata e ritaglio sul medesimo viewport', () {
    expect(CameraGuide.fraction, closeTo(.76 * .7, 1e-12));
    expect(CameraGuide.crop.left, closeTo(.234, 1e-12));
    expect(CameraGuide.crop.top, CameraGuide.crop.left);
    expect(CameraGuide.crop.right, closeTo(.766, 1e-12));
    final image = im.Image(width: 100, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 100; x++) {
        image.setPixelRgb(x, y, y, y, y);
      }
    }
    final result = decodeDisplay(
      Uint8List.fromList(im.encodePng(image)),
      crop: CameraGuide.crop,
    );
    final preview = im.decodeImage(result.preview)!;
    expect(preview.width, 53);
    expect(preview.height, 106);
    expect(preview.getPixel(0, 0).r, closeTo(46, 3));
  });
  test('Bridge trasmette la nuova cornice e conserva il timestamp', () async {
    const channel = MethodChannel('dev.danking.cardiograph/camera');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'capture');
          expect(
            (call.arguments as Map)['guideFraction'],
            CameraGuide.fraction,
          );
          return {
            'path': 'frame_test.jpg',
            'capturedAt': 123456789,
            'zone': 'Europe/Rome',
            'offsetMinutes': 60,
            'precise': true,
            'source': 'REALTIME',
            'width': 100,
            'height': 200,
          };
        });
    final service = NativeCaptureService();
    final photo = await service.capture();
    expect(photo.guideCrop, CameraGuide.crop);
    expect(photo.capturedAt.millisecondsSinceEpoch, 123456789);
    service.dispose();
  });
  test('Grafici: soglie strette, niente zeri nei giorni vuoti né curve', () {
    final data = AnalyticsData([
      reading('a', DateTime.utc(2024, 1, 1, 12)),
      reading('b', DateTime.utc(2024, 1, 4, 12), sys: 136, dia: 91, pulse: 101),
    ], period: CivilPeriod('2024-01-01', '2024-01-07'));
    final chart = metricChart(data, [
      Metric.systolic,
      Metric.diastolic,
    ], (_) {});
    expect(chart.lineBarsData.length, 2);
    for (final bar in chart.lineBarsData) {
      expect(bar.isCurved, false);
      expect(bar.spots.length, 2);
      expect(bar.belowBarData.show, false);
    }
    expect(
      chart.lineBarsData.first.spots.last.x -
          chart.lineBarsData.first.spots.first.x,
      3,
    );
    expect(chart.extraLinesData.horizontalLines.map((l) => l.y), [135, 90]);
    for (final metric in Metric.values) {
      expect(metricColor(metric, metric.threshold), isNot(Brand.red));
      expect(metricColor(metric, metric.threshold + 1), Brand.red);
    }
    final pulse = metricChart(data, [Metric.pulse], (_) {});
    expect(pulse.extraLinesData.horizontalLines.single.y, 100);
    expect(data.stats.systolic.mean, 135.5);
    final empty = AnalyticsData(
      [],
      period: CivilPeriod('2024-01-01', '2024-01-07'),
    );
    expect(empty.stats.count, 0);
    expect(empty.stats.pulse.mean, isNull);
  });
  test('Aggregazione conserva ogni picco e statistiche dai dati originali', () {
    final rows = [
      for (var i = 0; i < 199; i++)
        reading('$i', DateTime.utc(2024, 1, 1, 12), sys: 100),
      reading('peak', DateTime.utc(2024, 1, 1, 13), sys: 200),
    ];
    final data = AnalyticsData(
      rows,
      period: CivilPeriod('2024-01-01', '2024-03-31'),
    );
    expect(data.aggregated, true);
    expect(data.observations.length, 1);
    expect(data.stats.systolic.mean, 100.5);
    expect(data.stats.systolic.maximum, 200);
    final chart = metricChart(data, [Metric.systolic], (_) {});
    expect(chart.lineBarsData.map((b) => b.spots.single.y), [100.5, 100, 200]);
    expect(chart.maxY, greaterThan(200));
    final maxBar = chart.lineBarsData.last;
    final dot =
        maxBar.dotData.getDotPainter(maxBar.spots.single, 0, maxBar, 0)
            as FlDotCirclePainter;
    expect(dot.color, Brand.red);
    expect(metricColor(Metric.systolic, 135.001), Brand.red);
    final morning = AnalyticsData(
      [
        reading('night', DateTime.utc(2024, 1, 1, 6)),
        reading('day', DateTime.utc(2024, 1, 1, 12)),
      ],
      period: CivilPeriod('2024-01-01', '2024-01-01'),
      band: DayBand.morning,
    );
    expect(morning.rows.single.id, 'day');
  });
  test('SQL mensile: bisestile, anno e notte civile, soglie esatte', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = MeasurementRepository(db);
    try {
      for (final row in [
        reading('night', DateTime.utc(2024, 2, 29, 6, 59, 59)),
        reading('morning', DateTime.utc(2024, 2, 29, 7)),
        reading('edge1', DateTime.utc(2024, 2, 29, 13, 0, 59)),
        reading('afternoon', DateTime.utc(2024, 2, 29, 13, 1)),
        reading('edge2', DateTime.utc(2024, 2, 29, 19, 0, 59)),
        reading(
          'evening',
          DateTime.utc(2024, 2, 29, 19, 1),
          sys: 136,
          dia: 91,
          pulse: 101,
        ),
        reading('march', DateTime.utc(2024, 3, 1)),
        reading('year', DateTime.utc(2023, 12, 31, 23, 59, 59)),
      ]) {
        await repo.save(row);
      }
      final feb = await repo.monthSummary('2024-02');
      expect(feb.keys, ['2024-02-29']);
      final day = feb.values.single;
      expect(day.count, 6);
      expect(day.morning, 2);
      expect(day.afternoon, 2);
      expect(day.evening, 2);
      expect(day.highCount, 1);
      expect((await repo.monthSummary('2023-12')).values.single.count, 1);
      expect(await repo.monthSummary('2025-02'), isEmpty);
      final selected = await repo.list(
        period: CivilPeriod('2024-02-29', '2024-02-29'),
      );
      expect(selected.length, 6);
      expect(
        selected.singleWhere((m) => m.id == 'night').periodAnchorDate,
        '2024-02-28',
      );
    } finally {
      await repo.close();
      await db.close();
    }
  });
  testWidgets(
    'Home professionale: azione rossa circolare e tre fasce sulla stessa riga',
    (t) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: const CardioGraphApp(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Diario pressorio'), findsOneWidget);
      expect(find.textContaining('un passo alla volta'), findsNothing);
      expect(find.textContaining('Conserva le tue letture'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == Brand.red,
        ),
        findsOneWidget,
      );
      await t.ensureVisible(find.byKey(const ValueKey('home-band-row')));
      await t.pumpAndSettle();
      expect(
        t.getCenter(find.text('Mattina')).dy,
        closeTo(t.getCenter(find.text('Pomeriggio')).dy, 1),
      );
      expect(
        t.getCenter(find.text('Mattina')).dy,
        closeTo(t.getCenter(find.text('Sera')).dy, 1),
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await db.close();
    },
  );
  testWidgets(
    'Calendario: una query mese e una giorno, selezione persistente su modifica',
    (t) async {
      final semantics = t.ensureSemantics();
      final db = AppDatabase(NativeDatabase.memory());
      final repo = CountingRepo(db);
      await repo.save(reading('edit', DateTime.utc(2024, 2, 28, 6), sys: 123));
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
      await t.tap(find.text('Calendario').last);
      await t.pumpAndSettle();
      expect(repo.monthQueries, 1);
      expect(repo.dayQueries, 1);
      final day = find.byKey(const ValueKey('calendar-2024-02-28'));
      await t.ensureVisible(day);
      await t.pumpAndSettle();
      await t.tap(day);
      await t.pumpAndSettle();
      expect(repo.monthQueries, 1);
      expect(repo.dayQueries, 2);
      expect(t.getSemantics(day).label, contains('Sera 1'));
      expect(t.getSemantics(day).label, contains('28 febbraio 2024'));
      expect(t.getSemantics(day).label, contains('1 misurazioni'));
      final before = t
          .widget<Text>(find.byKey(const ValueKey('selected-calendar-day')))
          .data;
      await repo.save(
        reading('edit', DateTime.utc(2024, 2, 28, 6), sys: 136, revision: 1),
        editing: true,
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('selected-calendar-day')))
            .data,
        before,
      );
      expect(repo.monthQueries, 2);
      expect(repo.dayQueries, 3);
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('calendar-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = t.state<ScrollableState>(scrollable).position;
      final beforeDrag = position.pixels;
      final cell = t.getRect(day);
      await t.dragFrom(
        Offset(cell.center.dx, cell.center.dy.clamp(100.0, 450.0)),
        const Offset(0, -220),
      );
      await t.pumpAndSettle();
      expect(position.pixels, greaterThan(beforeDrag + 20));
      expect(find.textContaining('Oltre soglia'), findsNothing);
      semantics.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await repo.close();
      await db.close();
    },
  );
}
