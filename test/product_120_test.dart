import 'dart:convert';
import 'dart:io';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/app/providers.dart';
import 'package:cardiograph/app/version.dart';
import 'package:cardiograph/core/services/platform_services.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/features/backup/backup_codec.dart';
import 'package:cardiograph/features/backup/backup_service.dart';
import 'package:cardiograph/features/reminders/reminder_sync.dart';
import 'package:cardiograph/features/reports/report_model.dart';
import 'package:cardiograph/features/settings/about_page.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:timezone/data/latest.dart' as tzdata;
import 'repository_test.dart' show sample;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  late AppDatabase db;
  late MeasurementRepository repo;
  final calls = <MethodCall>[];
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MeasurementRepository(db);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidDocumentFileService.channel, (
          c,
        ) async {
          calls.add(c);
          if (c.method == 'takeLaunch') return false;
          if (c.method == 'reminderStatus') {
            return {
              'allowed': true,
              'exact': true,
              'zone': 'Europe/Rome',
              'slots': [
                for (final (id, minute) in [
                  (1000, 600),
                  (1600, 960),
                  (2100, 1260),
                ])
                  {
                    'id': id,
                    'minutes': minute,
                    'enabled': false,
                    'next': '2026-11-16T10:00:00+01:00',
                  },
              ],
            };
          }
          return null;
        });
  });
  tearDown(() async {
    await repo.close();
    await db.close();
  });
  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async => db),
      zoneLookupProvider.overrideWithValue(() async => 'Europe/Rome'),
    ],
    child: const CardioGraphApp(),
  );

  test(
    'Coverage indicizzata: notte nella sessione precedente, CRUD e riattivazione',
    () async {
      final before = sample(
        id: 'night',
        instant: DateTime.utc(2026, 11, 15, 1),
      );
      await repo.save(before);
      expect((await repo.reminderCoverage())['2100'], ['2026-11-14']);
      final m = sample(
        id: 'morning',
        instant: DateTime.utc(2026, 11, 15, 8, 30),
      );
      await repo.save(m);
      expect((await repo.reminderCoverage())['1000'], ['2026-11-15']);
      await repo.delete(m);
      expect((await repo.reminderCoverage())['1000'], isEmpty);
      await repo.restore(m);
      final edited = sample(
        id: 'morning',
        instant: DateTime.utc(2026, 11, 15, 14),
        revision: 1,
      );
      await repo.save(edited, editing: true);
      final coverage = await repo.reminderCoverage();
      expect(coverage['1000'], isEmpty);
      expect(coverage['1600'], ['2026-11-15']);
    },
  );
  test(
    'Sincronizzazione persistente ordinata dopo commit e dopo rollback',
    () async {
      late MeasurementRepository hooked;
      hooked = MeasurementRepository(
        db,
        beforeMutation: () => ReminderSync.begin(forceForTest: true),
        afterMutation: () => ReminderSync(hooked).apply(forceForTest: true),
      );
      await hooked.save(sample());
      expect(calls.map((c) => c.method), [
        'beginReminderMutation',
        'applyReminderPreferences',
      ]);
      var payload = Map.from(calls.last.arguments as Map);
      expect((payload['coverage'] as Map)['1000'], ['2026-11-14']);
      await hooked.delete(sample());
      payload = Map.from(calls.last.arguments as Map);
      expect((payload['coverage'] as Map)['1000'], isEmpty);
      // Failed edit must republish actual committed coverage rather than staged data.
      await expectLater(
        hooked.save(sample(revision: 2), editing: true),
        throwsStateError,
      );
      expect(calls.last.method, 'applyReminderPreferences');
      await hooked.close();
    },
  );
  test(
    'Orari validi sui confini; preferenze persistite e restore riconciliato',
    () async {
      for (final (i, m) in [
        (0, 420),
        (0, 780),
        (1, 781),
        (1, 1140),
        (2, 1141),
        (2, 0),
        (2, 419),
      ]) {
        expect(validReminderMinute(i, m), isTrue);
      }
      for (final (i, m) in [
        (0, 419),
        (0, 781),
        (1, 780),
        (1, 1141),
        (2, 420),
        (2, 1140),
        (2, 1440),
      ]) {
        expect(validReminderMinute(i, m), isFalse);
      }
      final service = BackupService(
        repo,
        readReminders: () async =>
            (await SettingsRepository(db).read()).reminders.toList(),
        applyReminders: (_) => ReminderSync(repo).apply(forceForTest: true),
        preferencesChanged: () {},
      );
      await service.setReminderTime(2100, 120);
      expect((await SettingsRepository(db).read()).reminderMinutes, [
        600,
        960,
        120,
      ]);
      await expectLater(
        service.setReminderTime(1000, 900),
        throwsArgumentError,
      );
      await service.replace(
        BackupArchive(
          [sample()],
          const AppSettings(
            reminderMinutes: [570, 900, 60],
            reminders: [true, true, true],
          ),
        ),
      );
      final payload = Map.from(calls.last.arguments as Map);
      expect(payload['minutes'], [570, 900, 60]);
      expect(payload['enabled'], [true, true, true]);
      expect((payload['coverage'] as Map)['1000'], ['2026-11-14']);
    },
  );
  test(
    'Backup schema 3: custom times e migrazioni compatibili v1/v2',
    () async {
      final a = BackupArchive([
        sample(),
      ], const AppSettings(reminderMinutes: [570, 900, 120]));
      for (final password in [null, 'password-di-test']) {
        final bytes = await encodeBackup(
          a,
          now: DateTime.utc(2026, 11, 15),
          passphrase: password,
        );
        final result = await BackupEnvelope.inspect(
          bytes,
        ).decode(passphrase: password);
        expect(result.settings.reminderMinutes, [570, 900, 120]);
      }
      for (final version in [1, 2]) {
        final p = jsonDecode(canonical(a.payload)) as Map<String, dynamic>;
        p['schemaVersion'] = version;
        final prefs = p['preferences'] as Map;
        prefs.remove('reminderMinutes');
        if (version == 2) prefs['opaque'] = true;
        final migrated = BackupArchive.validate(p);
        expect(migrated.settings.reminderMinutes, [600, 960, 1260]);
        expect(migrated.settings.opaque, isFalse);
        expect(migrated.payload['schemaVersion'], 3);
      }
      final bad = jsonDecode(canonical(a.payload)) as Map<String, dynamic>;
      (bad['preferences'] as Map)['reminderMinutes'] = [100, 900, 1260];
      expect(() => BackupArchive.validate(bad), throwsA(isA<BackupFailure>()));
    },
  );
  test(
    'Migrazione reale v3→v4: dati/flag conservati, trasparenze riattivate',
    () async {
      final dir = await Directory.systemTemp.createTemp('cardiograph-v4-');
      final f = File('${dir.path}/v3.sqlite');
      final raw = sqlite.sqlite3.open(f.path);
      raw.execute(measurementV1);
      raw.execute(
        "ALTER TABLE measurements ADD COLUMN note TEXT NOT NULL DEFAULT ''",
      );
      final m = sample(note: 'Migrazione conservativa');
      raw.execute(
        'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
        m.values.values.toList(),
      );
      raw.execute(
        'CREATE TABLE app_settings(id INTEGER PRIMARY KEY,protect_backup_with_password INTEGER,opaque INTEGER,reminder_morning INTEGER,reminder_afternoon INTEGER,reminder_evening INTEGER,last_backup_utc INTEGER)',
      );
      raw.execute('INSERT INTO app_settings VALUES(1,1,1,1,0,1,1234)');
      raw.execute(
        'CREATE TABLE archive_operation(id TEXT PRIMARY KEY,state TEXT,recovery TEXT,recovery_hash TEXT,staging TEXT)',
      );
      raw.execute('PRAGMA user_version=3');
      raw.close();
      final migrated = AppDatabase(NativeDatabase(f));
      final r = MeasurementRepository(migrated);
      try {
        expect((await r.list()).single.values, m.values);
        final prefs = await SettingsRepository(migrated).read();
        expect(prefs.protectBackupWithPassword, isTrue);
        expect(prefs.reminders, [true, false, true]);
        expect(prefs.reminderMinutes, [600, 960, 1260]);
        expect(prefs.lastBackupUtc!.millisecondsSinceEpoch, 1234);
        expect(
          (await migrated
                  .customSelect('SELECT opaque FROM app_settings')
                  .getSingle())
              .read<int>('opaque'),
          0,
        );
      } finally {
        await r.close();
        await migrated.close();
        await f.delete();
        await dir.delete();
      }
    },
  );
  testWidgets(
    'Impostazioni: esattamente tre accessi e Info con asset/link browser',
    (t) async {
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Impostazioni'));
      await t.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
      for (final label in ['Promemoria', 'Backup e dati', 'Info']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Leggibilità'), findsNothing);
      expect(find.text('Riduci trasparenze'), findsNothing);
      await t.tap(find.text('Info'));
      await t.pumpAndSettle();
      expect(find.text(AppVersion.label), findsOneWidget);
      expect(find.text('Dan King'), findsOneWidget);
      expect(find.text('Flutter & Android Developer'), findsOneWidget);
      expect(
        t
            .widgetList<Image>(find.byType(Image))
            .any(
              (i) =>
                  i.image is AssetImage &&
                  (i.image as AssetImage).assetName ==
                      'assets/sviluppatore.jpg',
            ),
        isTrue,
      );
      await t.ensureVisible(find.byKey(const ValueKey('repository-link')));
      await t.tap(find.byKey(const ValueKey('repository-link')));
      await t.pumpAndSettle();
      expect(calls.any((c) => c.method == 'openRepository'), isTrue);
      await t.tap(find.text('Guida breve'));
      await t.pumpAndSettle();
      expect(find.byType(GuidePage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Tutte le misurazioni: Andamento senza filtro data e Report periodo reale',
    (t) async {
      await repo.save(sample(instant: DateTime.utc(2020, 1, 2, 9)));
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text('Andamento').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Tutte le misurazioni'));
      await t.pumpAndSettle();
      expect(find.text('2020-01-02 – 2020-01-02'), findsOneWidget);
      expect(find.textContaining('1 lettura'), findsWidgets);
      await t.tap(find.text('Report').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<ReportMode>));
      await t.pumpAndSettle();
      await t.tap(find.text('Tutte le misurazioni').last);
      await t.pumpAndSettle();
      expect(find.text('02/01/2020 – 02/01/2020'), findsOneWidget);
      expect(
        ReportPeriod.covering(await repo.snapshotAll()).civil.start,
        '2020-01-02',
      );
      expect(() => ReportPeriod.covering([]), throwsStateError);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Preferenza opaca legacy ignorata nel tema reale', (t) async {
    await SettingsRepository(db).save(const AppSettings(opaque: true));
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    final element = t.element(find.byType(MaterialApp));
    expect(ProviderScope.containerOf(element).read(opaqueProvider), isFalse);
    expect(
      t
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .any((f) => f.enabled),
      isTrue,
    );
    await t.pumpWidget(const SizedBox());
  });
}
