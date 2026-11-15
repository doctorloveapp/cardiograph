import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/core/time/measurement_time.dart';
import 'package:cardiograph/features/measurements/measurement.dart';

Measurement sample({
  String id = 'test',
  int systolic = 123,
  DateTime? instant,
  String note = '',
  int revision = 0,
}) {
  final utc = instant ?? DateTime.utc(2026, 11, 14, 11, 30, 45);
  final wall = utc.add(const Duration(hours: 1));
  return Measurement(
    id: id,
    systolic: systolic,
    diastolic: 88,
    pulse: 64,
    measuredAtUtc: utc,
    zone: 'Europe/Rome',
    offsetMinutes: 60,
    localDate: dateKey(wall),
    localTime: timeKey(wall),
    createdAtUtc: utc,
    updatedAtUtc: utc,
    revision: revision,
    note: note,
  );
}

class FakeVault implements ArchiveKeyVault {
  String? value;
  FakeVault([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

void main() {
  // Test databases have distinct executors/files; production owns a single provider.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late MeasurementRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MeasurementRepository(db);
  });
  tearDown(() async {
    await repo.close();
    await db.close();
  });
  test(
    'Salvataggio concorrente idempotente, doppioni legittimi conservati',
    () async {
      final m = sample();
      await Future.wait([repo.save(m), repo.save(m)]);
      expect((await repo.list()).length, 1);
      final second = sample(id: 'second');
      expect(await repo.possibleDuplicate(second), isTrue);
      await repo.save(second);
      expect((await repo.list()).length, 2);
      expect((await repo.list()).map((m) => m.id), ['second', 'test']);
    },
  );
  test('Stream reattivo post commit, eliminazione e Undo identico', () async {
    final iterator = StreamIterator(repo.watch());
    await iterator.moveNext();
    expect(iterator.current, isEmpty);
    final m = sample(note: 'Nota conservata');
    await repo.save(m);
    await iterator.moveNext();
    expect(iterator.current.single.note, m.note);
    await repo.delete(m);
    await iterator.moveNext();
    expect(iterator.current, isEmpty);
    await repo.restore(m);
    await iterator.moveNext();
    expect(iterator.current.single.values, m.values);
    await iterator.cancel();
  });
  test(
    'Modifica controllata preserva scatto originale, revisione obsoleta rifiutata',
    () async {
      final original = Measurement.fromRow({
        ...sample().values,
        'source': 'camera',
        'original_captured_at_utc': DateTime.utc(
          2026,
          11,
          14,
          11,
          30,
          45,
        ).millisecondsSinceEpoch,
      });
      await repo.save(original);
      final edit = Measurement.fromRow({
        ...original.values,
        'systolic': 136,
        'revision': 1,
        'note': 'Modificata',
      });
      await repo.save(edit, editing: true);
      final got = (await repo.list()).single;
      expect(got.originalCapturedAtUtc, original.originalCapturedAtUtc);
      expect(got.measuredAtUtc, original.measuredAtUtc);
      expect(got.source, 'camera');
      await expectLater(repo.save(edit, editing: true), throwsStateError);
      expect((await repo.list()).single.systolic, 136);
    },
  );
  test('Filtri civili inclusivi, notte e rollback senza perdita', () async {
    await repo.save(
      sample(id: 'night', instant: DateTime.utc(2026, 11, 14, 23, 30)),
    );
    expect(
      await repo.list(period: CivilPeriod('2026-11-14', '2026-11-14')),
      isEmpty,
    );
    final night = (await repo.list(
      period: CivilPeriod('2026-11-15', '2026-11-15'),
    )).single;
    expect(night.periodAnchorDate, '2026-11-14');
    await expectLater(
      db.transaction(() async {
        await db.customStatement('DELETE FROM measurements');
        throw StateError('I/O simulato');
      }),
      throwsStateError,
    );
    expect((await repo.list()).length, 1);
    await expectLater(
      repo.save(sample(id: 'bad', systolic: 0)),
      throwsArgumentError,
    );
    await expectLater(
      db.customStatement('UPDATE measurements SET pulse=0'),
      throwsA(anything),
    );
    expect((await repo.list()).single.pulse, 64);
  });
  test(
    'Settings senza password di default, aggiornamento transazionale',
    () async {
      final settings = SettingsRepository(db);
      expect((await settings.read()).protectBackupWithPassword, isFalse);
      await settings.save(const AppSettings(protectBackupWithPassword: true));
      expect((await settings.read()).protectBackupWithPassword, isTrue);
    },
  );
  test(
    'Migrazione reale v1 → v4 conserva ID, istanti e campi esistenti',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cardiograph-migration-',
      );
      final file = File('${directory.path}/archive.sqlite');
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(measurementV1);
      raw.execute('PRAGMA user_version=1');
      final values = Map<String, Object?>.from(sample(id: 'old').values)
        ..remove('note');
      raw.execute(
        'INSERT INTO measurements (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
        values.values.toList(),
      );
      raw.close();
      final migrated = AppDatabase(NativeDatabase(file));
      final migratedRepo = MeasurementRepository(migrated);
      try {
        final old = (await migratedRepo.list()).single;
        expect(old.id, 'old');
        expect(old.measuredAtUtc, sample().measuredAtUtc);
        expect(old.note, '');
        expect(
          (await SettingsRepository(migrated).read()).protectBackupWithPassword,
          isFalse,
        );
        final indexes = await migrated
            .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
            .get();
        expect(
          indexes.map((i) => i.read<String>('name')),
          containsAll(['measurements_local_date', 'measurements_utc']),
        );
        expect(
          (await migrated.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          4,
        );
      } finally {
        await migratedRepo.close();
        await migrated.close();
        final target = await directory.resolveSymbolicLinks();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        if (!target.startsWith('$root${Platform.pathSeparator}cardiograph-')) {
          throw StateError('Unexpected temporary directory');
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );
  test(
    'Database cifrato su file/isolate, riapertura e chiavi mancanti/errate senza sovrascrittura',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cardiograph-encryption-',
      );
      final file = File('${directory.path}/archive.sqlite');
      final vault = FakeVault();
      try {
        final first = await openArchive(file, vault);
        final r = MeasurementRepository(first);
        await r.save(sample());
        await r.close();
        await first.close();
        final before = await file.readAsBytes();
        expect(
          utf8
              .decode(before.take(16).toList(), allowMalformed: true)
              .startsWith('SQLite format 3'),
          isFalse,
        );
        expect(base64Url.decode(vault.value!).length, 32);
        final second = await openArchive(file, vault);
        final r2 = MeasurementRepository(second);
        expect((await r2.list()).single.systolic, 123);
        await r2.close();
        await second.close();
        await expectLater(
          openArchive(file, FakeVault()),
          throwsA(isA<ArchiveUnavailable>()),
        );
        await expectLater(
          openArchive(file, FakeVault(base64Url.encode(List.filled(32, 1)))),
          throwsA(isA<ArchiveUnavailable>()),
        );
        expect(await file.readAsBytes(), before);
      } finally {
        final target = await directory.resolveSymbolicLinks();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        if (!target.startsWith('$root${Platform.pathSeparator}cardiograph-')) {
          throw StateError('Unexpected temporary directory');
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );
}
