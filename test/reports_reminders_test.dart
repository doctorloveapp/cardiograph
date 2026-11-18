import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/core/services/platform_services.dart';
import 'package:cardiograph/features/reports/report_model.dart';
import 'package:cardiograph/features/reports/report_pdf.dart';
import 'package:cardiograph/features/reminders/reminders.dart';
import 'package:cardiograph/features/analytics/analytics_model.dart';
import 'analytics_calendar_test.dart' show reading;
import 'package:cardiograph/features/measurements/measurement.dart';

void main() {
  test(
    'Scale PDF: valori regolari leggibili, estremi compresi, unità separate',
    () {
      for (final values in [
        [60, 85, 90, 100, 130, 140, 160],
        [60, 100],
        [1, 999],
        [80, 80],
      ]) {
        final scale = ReportChartScale.fromValues(values);
        expect(
          scale.minimum,
          lessThanOrEqualTo(values.reduce((a, b) => a < b ? a : b)),
        );
        expect(
          scale.maximum,
          greaterThanOrEqualTo(values.reduce((a, b) => a > b ? a : b)),
        );
        expect(scale.minimum, greaterThanOrEqualTo(0));
        expect(scale.ticks.length, inInclusiveRange(3, 10));
        for (var i = 1; i < scale.ticks.length; i++) {
          expect(scale.ticks[i] - scale.ticks[i - 1], scale.step);
        }
      }
      final pressure = ReportChartScale.fromValues([
        60,
        85,
        90,
        100,
        130,
        140,
        160,
      ]);
      final pulse = ReportChartScale.fromValues([60, 100]);
      expect(pressure.ticks, isNot(pulse.ticks));
      expect(() => ReportChartScale.fromValues([]), throwsArgumentError);
    },
  );
  test(
    'PDF tutte le categorie: torta vettoriale, legenda e autore vuoto',
    () async {
      final rows = [
        for (final (i, sys, dia, pulse) in [
          (1, 85, 55, 59),
          (2, 110, 70, 60),
          (3, 135, 80, 99),
          (4, 145, 78, 100),
          (5, 165, 80, 110),
        ])
          reading(
            'range-$i',
            DateTime.utc(2024, 2, i, 12),
            sys: sys,
            dia: dia,
            pulse: pulse,
          ),
      ];
      final snapshot = ReportSnapshot(
        period: ReportPeriod.month(2024, 2),
        rows: rows,
        generatedAt: DateTime(2024, 3, 1),
      );
      final bytes = await buildReportPdf((
        snapshot,
        File('assets/logo.png').readAsBytesSync(),
        File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
      ));
      expect(latin1.decode(bytes).toLowerCase(), isNot(contains('dan king')));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        greaterThanOrEqualTo(3),
      );
      if (Platform.environment['CARDIOGRAPH_PDF_SAMPLES'] == '1') {
        Directory('output/pdf').createSync(recursive: true);
        File('output/pdf/ranges.pdf').writeAsBytesSync(bytes);
      }
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Quattro periodi civili: settimana a cavallo anno, bisestile, DST, intervallo inclusivo',
    () {
      expect(
        ReportPeriod.day(DateTime(2024, 3, 31, 6)).civil.start,
        '2024-03-31',
      );
      final week = ReportPeriod.week(DateTime(2025, 1, 1));
      expect(week.civil.start, '2024-12-30');
      expect(week.civil.end, '2025-01-05');
      expect(ReportPeriod.month(2024, 2).civil.end, '2024-02-29');
      expect(ReportPeriod.month(2026, 12).civil.end, '2026-12-31');
      final custom = ReportPeriod.custom(
        DateTime(2024, 3, 30),
        DateTime(2024, 4, 1),
      );
      expect(custom.civil.contains('2024-04-01'), isTrue);
      expect(
        () => ReportPeriod.custom(DateTime(2025), DateTime(2024)),
        throwsArgumentError,
      );
    },
  );
  test(
    'Snapshot transazionale, giorno civile notturno, soglie strette e periodo vuoto',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = MeasurementRepository(db);
      try {
        await repo.save(reading('night', DateTime.utc(2024, 3, 31, 6)));
        final period = ReportPeriod.day(DateTime(2024, 3, 31));
        final rows = await repo.snapshot(period.civil);
        final snapshot = ReportSnapshot(
          period: period,
          rows: rows,
          generatedAt: DateTime(2024, 4),
        );
        expect(snapshot.rows.single.nocturnal, isTrue);
        expect(snapshot.stats.count, 1);
        expect(snapshot.stats.systolic.mean, 135);
        expect(Metric.systolic.high(129.99), isFalse);
        expect(Metric.systolic.high(130), isTrue);
        await repo.delete(rows.single);
        expect(snapshot.rows.length, 1);
        final empty = ReportSnapshot(
          period: period,
          rows: await repo.snapshot(period.civil),
          generatedAt: DateTime(2024, 4),
        );
        expect(empty.stats.systolic.mean, isNull);
        await expectLater(
          buildReportPdf((empty, Uint8List(0), Uint8List(0))),
          throwsStateError,
        );
      } finally {
        await repo.close();
        await db.close();
      }
    },
  );
  test(
    'PDF A4 corto e multipagina, font accenti, note lunghe e identità autore assente',
    () async {
      final logo = File('assets/logo.png').readAsBytesSync();
      final font = File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();
      for (final n in [2, 72]) {
        final rows = [
          for (var i = 0; i < n; i++)
            reading(
              'sample-$i',
              DateTime.utc(2024, 2, 1 + i % 29, 6 + i % 16),
              sys: i.isEven ? 136 : 135,
              dia: i.isEven ? 91 : 90,
              pulse: i.isEven ? 101 : 100,
            ),
        ];
        final withNotes = rows
            .map(
              (m) => Map<String, dynamic>.from(m.values)
                ..['note'] = m.id.endsWith('0')
                    ? 'Misurazione confermata: attività, caffè, qualità del riposo. ${List.filled(14, 'Nota clinica con accenti: è, à, ù.').join(' ')}'
                          .substring(0, 490)
                    : 'Caffè e attività quotidiana.',
            )
            .map(
              (m) =>
                  // Model round trip also checks real persisted note representation.
                  Measurement.fromRow(m),
            )
            .toList();
        final snapshot = ReportSnapshot(
          period: ReportPeriod.month(2024, 2),
          rows: withNotes,
          generatedAt: DateTime(2024, 3, 1, 12),
          heading: 'Campione sintetico · attività e qualità',
        );
        final bytes = await buildReportPdf((snapshot, logo, font));
        final raw = latin1.decode(bytes);
        expect(raw.startsWith('%PDF-'), isTrue);
        expect(raw.toLowerCase(), isNot(contains('dan king')));
        final pages = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
        expect(pages, greaterThanOrEqualTo(3));
        if (Platform.environment['CARDIOGRAPH_PDF_SAMPLES'] == '1') {
          final directory = Directory('output/pdf')
            ..createSync(recursive: true);
          File(
            '${directory.path}/${n == 2 ? 'breve' : 'multipagina'}.pdf',
          ).writeAsBytesSync(bytes);
        }
      }
      expect(
        () => ReportSnapshot(
          period: ReportPeriod.month(2024, 2),
          rows: [],
          generatedAt: DateTime(2024),
          heading: 'Dan King',
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'Note limite: 500 caratteri, parole senza spazi e centinaia di a capo',
    () async {
      final logo = File('assets/logo.png').readAsBytesSync();
      final font = File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();
      final rows = [
        for (final note in ['W' * 500, 'a\n' * 250, 'è ' * 250])
          Measurement.fromRow(
            Map<String, dynamic>.from(
              reading(note.substring(0, 2), DateTime.utc(2024, 2, 1, 8)).values,
            )..['note'] = note,
          ),
      ];
      final bytes = await buildReportPdf((
        ReportSnapshot(
          period: ReportPeriod.month(2024, 2),
          rows: rows,
          generatedAt: DateTime(2024, 3),
        ),
        logo,
        font,
      ));
      expect(bytes.length, greaterThan(1000));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
        lessThan(6),
      );
    },
  );
  test(
    'SAF distingue salvataggio, annullamento ed errore; permesso richiesto solo all’attivazione',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      var saved = false;
      messenger.setMockMethodCallHandler(AndroidDocumentFileService.channel, (
        c,
      ) async {
        calls.add(c.method);
        if (c.method == 'save') return saved;
        if (c.method == 'setReminder' || c.method == 'requestNotifications') {
          return {
            'allowed': false,
            'exact': false,
            'zone': 'Europe/Rome',
            'slots': [],
          };
        }
        return null;
      });
      final files = AndroidDocumentFileService();
      expect(await files.save('test.pdf', [1]), isFalse);
      saved = true;
      expect(await files.save('test.pdf', [1]), isTrue);
      calls.clear();
      final reminders = AndroidReminderScheduler();
      await reminders.enable(1000, false);
      expect(calls, ['setReminder']);
      calls.clear();
      final status = await reminders.enable(1000, true);
      expect(calls, ['requestNotifications', 'setReminder']);
      expect(status.allowed, isFalse);
      messenger.setMockMethodCallHandler(
        AndroidDocumentFileService.channel,
        (c) async => throw PlatformException(code: 'DOCUMENT'),
      );
      await expectLater(
        files.save('test.pdf', [1]),
        throwsA(isA<PlatformException>()),
      );
      messenger.setMockMethodCallHandler(
        AndroidDocumentFileService.channel,
        null,
      );
    },
  );
  testWidgets('Tap notifica da cold start apre scelta Foto/Manuale', (t) async {
    var pending = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidDocumentFileService.channel, (
          c,
        ) async {
          if (c.method == 'takeLaunch') {
            final v = pending;
            pending = false;
            return v;
          }
          return null;
        });
    final db = AppDatabase(NativeDatabase.memory());
    await t.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: const CardioGraphApp(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Scatta foto'), findsOneWidget);
    expect(find.text('Inserisci a mano'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidDocumentFileService.channel, null);
  });
}
