import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/app/providers.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/features/measurements/measurement.dart';
import 'package:cardiograph/features/backup/backup_codec.dart';
import 'package:cardiograph/features/backup/backup_service.dart';
import 'package:cardiograph/core/time/measurement_time.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'QA isolata Android: database cifrato, 10k/50k, Argon2 e frame',
    (t) async {
      // Never run stress or preference changes on the user's physical device.
      if (const String.fromEnvironment('QA_EMULATOR') != 'true') {
        throw StateError('Richiesto QA_EMULATOR=true su emulatore');
      }
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/qa_isolated',
      )..createSync();
      final file = File('${dir.path}/stress.sqlite');
      final db = await openArchive(file, _Vault());
      final repo = MeasurementRepository(db);
      final timings = <FrameTiming>[];
      void record(List<FrameTiming> f) => timings.addAll(f);
      try {
        for (final count in [10000, 50000]) {
          final before = count == 10000 ? 0 : 10000;
          await db.batch((b) {
            for (var i = before; i < count; i++) {
              final wall = DateTime.utc(
                2026,
                11,
                1 + i % 15,
                8 + i % 13,
                i % 60,
                i % 60,
              );
              final m = Measurement(
                id: 'qa-$i',
                systolic: 125 + i % 20,
                diastolic: 80 + i % 15,
                pulse: 60 + i % 45,
                measuredAtUtc: wall.subtract(const Duration(hours: 1)),
                zone: 'Europe/Rome',
                offsetMinutes: 60,
                localDate: dateKey(wall),
                localTime: timeKey(wall),
                createdAtUtc: wall,
                updatedAtUtc: wall,
                note: 'Dato sintetico QA',
              );
              b.customStatement(
                'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
                m.values.values.toList(),
              );
            }
          });
          final samples = <int>[];
          for (var i = 0; i < 25; i++) {
            final clock = Stopwatch()..start();
            final month = await repo.monthSummary('2026-11');
            samples.add(clock.elapsedMicroseconds);
            expect(month.values.fold<int>(0, (n, d) => n + d.count), count);
          }
          samples.sort();
          // ignore: avoid_print
          print('QA_RELEASE query_month n=$count p95_ms=${samples[23] / 1000}');
        }
        final rows = await repo.list();
        expect(rows.length, 50000);
        final archive = BackupArchive(rows.take(2), const AppSettings());
        final crypto = Stopwatch()..start();
        final bytes = await compute(encodeBackupWorker, (
          archive,
          'password-QA-isolata',
          DateTime.now(),
        ));
        // ignore: avoid_print
        print('QA_RELEASE Argon2+AES_export_ms=${crypto.elapsedMilliseconds}');
        await expectLater(
          compute(decodeBackupWorker, (bytes, 'errata')),
          throwsA(isA<BackupFailure>()),
        );
        final decoded = await compute(decodeBackupWorker, (
          bytes,
          'password-QA-isolata',
        ));
        expect(decoded.rows.length, 2);
        SchedulerBinding.instance.addTimingsCallback(record);
        final home = Stopwatch()..start();
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              opaqueProvider.overrideWith(_QaOpacity.new),
              databaseProvider.overrideWith((ref) async => db),
              measurementRepositoryProvider.overrideWith((ref) async => repo),
            ],
            child: const CardioGraphApp(),
          ),
        );
        await t.pumpAndSettle();
        // ignore: avoid_print
        print('QA_RELEASE Home_50k_ready_ms=${home.elapsedMilliseconds}');
        for (final label in ['Andamento', 'Calendario', 'Report', 'Home']) {
          await t.tap(find.text(label).last);
          await t.pumpAndSettle();
          await t.fling(
            find.byType(Scrollable).first,
            const Offset(0, -400),
            800,
          );
          await t.pumpAndSettle();
        }
        await t.pump(const Duration(seconds: 1));
        final good = timings
            .where((f) => f.totalSpan.inMicroseconds <= 16700)
            .length;
        // ignore: avoid_print
        print(
          'QA_RELEASE frames=${timings.length} total_span_within_16_7ms_percent=${timings.isEmpty ? 0 : 100 * good / timings.length} renderer=emulator',
        );
        await t.pumpWidget(const SizedBox());
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(record);
        await repo.close();
        await db.close();
        for (final f in dir.listSync().whereType<File>()) {
          await f.delete();
        }
        await dir.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class _QaOpacity extends OpaqueController {
  @override
  bool build() => const bool.fromEnvironment('QA_OPAQUE');
}

class _Vault implements ArchiveKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}
