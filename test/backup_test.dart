import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/features/backup/backup_codec.dart';
import 'package:cardiograph/features/backup/backup_service.dart';
import 'package:cardiograph/features/backup/backup_settings.dart';
import 'package:cardiograph/features/settings/settings_page.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/core/design_system/components.dart';
import 'package:cardiograph/core/services/platform_services.dart';
import 'package:cardiograph/features/measurements/measurement.dart';
import 'repository_test.dart' show sample, FakeVault;

class CancelFiles extends AndroidDocumentFileService {
  bool called = false;
  @override
  Future<bool> save(String name, List<int> bytes) async {
    called = true;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late MeasurementRepository repo;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MeasurementRepository(db);
  });
  tearDown(() async {
    await repo.close();
    await db.close();
  });
  BackupService service({
    Future<void> Function(List<bool>)? apply,
    Future<void> Function(String)? checkpoint,
  }) => BackupService(
    repo,
    readReminders: () async => [false, true, false],
    applyReminders: apply ?? (_) async {},
    preferencesChanged: () {},
    checkpoint: checkpoint,
  );
  final archive = BackupArchive([
    sample(note: 'Attività, caffè e qualità.\nConfermata dall’utente.'),
  ], const AppSettings(opaque: true, reminders: [true, false, true]));
  final now = DateTime.utc(2026, 11, 14, 12);
  Uint8List wire(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  Map<String, dynamic> map(Uint8List value) =>
      jsonDecode(utf8.decode(value)) as Map<String, dynamic>;

  group('Formato portabile', () {
    late Uint8List plain, encrypted;
    setUpAll(() async {
      plain = await encodeBackup(archive, now: now);
      encrypted = await encodeBackup(
        archive,
        now: now,
        passphrase: 'prova-portabile-2026',
      );
    });
    test(
      'Round trip standard senza password, checksum canonico e campi esclusi',
      () async {
        final decoded = await BackupEnvelope.inspect(plain).decode();
        expect(canonical(decoded.payload), canonical(archive.payload));
        expect(BackupEnvelope.inspect(plain).encrypted, isFalse);
        final reordered = map(plain);
        final header = reordered['header'] as Map;
        reordered['header'] = Map.fromEntries(header.entries.toList().reversed);
        expect(
          (await BackupEnvelope.inspect(
            wire(reordered),
          ).decode()).rows.single.note,
          archive.rows.single.note,
        );
        final text = utf8.decode(plain);
        for (final secret in [
          'keyStore',
          'dbKey',
          'permissions',
          'temporaryPhoto',
          'lastBackupUtc',
          'last_backup_utc',
        ]) {
          expect(text, isNot(contains(secret)));
        }
      },
    );
    test(
      'AES-256-GCM / Argon2id e tutte le 4 combinazioni flag/file',
      () async {
        final h = map(encrypted)['header'] as Map;
        expect(h['kdf'], containsPair('memoryKiB', 65536));
        expect(h['kdf'], containsPair('parallelism', 1));
        expect(h['kdf'], containsPair('iterations', 3));
        expect(base64Decode(h['nonce'] as String).length, 12);
        expect(base64Decode(map(encrypted)['tag'] as String).length, 16);
        for (final currentFlag in [false, true]) {
          final currentSettings = AppSettings(
            protectBackupWithPassword: currentFlag,
          );
          for (final bytes in [plain, encrypted]) {
            final envelope = BackupEnvelope.inspect(bytes);
            // The live setting never participates in the import password decision.
            expect(currentSettings.protectBackupWithPassword, currentFlag);
            final result = await envelope.decode(
              passphrase: envelope.encrypted ? 'prova-portabile-2026' : null,
            );
            expect(canonical(result.payload), canonical(archive.payload));
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
    test(
      'Checksum alterato, file troncato, limiti, versioni future e KDF abusivo',
      () async {
        final tampered = map(plain);
        (tampered['payload'] as Map)['schemaVersion'] = 1;
        await expectLater(
          BackupEnvelope.inspect(wire(tampered)).decode(),
          throwsA(isA<BackupFailure>()),
        );
        expect(
          () => BackupEnvelope.inspect(
            Uint8List.sublistView(plain, 0, plain.length - 3),
          ),
          throwsA(isA<BackupFailure>()),
        );
        expect(
          () => BackupEnvelope.inspect(Uint8List(maxBackupBytes + 1)),
          throwsA(isA<BackupFailure>()),
        );
        final future = map(plain);
        (future['header'] as Map)['formatVersion'] = 2;
        expect(
          () => BackupEnvelope.inspect(wire(future)),
          throwsA(isA<BackupFailure>()),
        );
        final evil = map(encrypted);
        ((evil['header'] as Map)['kdf'] as Map)['memoryKiB'] = 1073741824;
        expect(
          () => BackupEnvelope.inspect(wire(evil)),
          throwsA(isA<BackupFailure>()),
        );
        final duplicate =
            '{"header":${jsonEncode(map(plain)['header'])},"header":{}}';
        expect(
          () => BackupEnvelope.inspect(
            Uint8List.fromList(utf8.encode(duplicate)),
          ),
          throwsA(isA<BackupFailure>()),
        );
      },
    );
    test(
      'Password errata, tag e AAD alterati rifiutati',
      () async {
        await expectLater(
          BackupEnvelope.inspect(
            encrypted,
          ).decode(passphrase: 'password-errata'),
          throwsA(isA<BackupFailure>()),
        );
        final badTag = map(encrypted);
        badTag['tag'] = base64Encode(List.filled(16, 0));
        await expectLater(
          BackupEnvelope.inspect(
            wire(badTag),
          ).decode(passphrase: 'prova-portabile-2026'),
          throwsA(isA<BackupFailure>()),
        );
        final badAad = map(encrypted);
        (badAad['header'] as Map)['appVersion'] = '0.0.1';
        await expectLater(
          BackupEnvelope.inspect(
            wire(badAad),
          ).decode(passphrase: 'prova-portabile-2026'),
          throwsA(isA<BackupFailure>()),
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
  test(
    'Schema integrale: ID, date, offset, limiti, origine e migrazione v1',
    () {
      for (final mutation in [
        (Map<String, dynamic> p) =>
            (p['readings'] as List).add((p['readings'] as List).first),
        (Map<String, dynamic> p) =>
            ((p['readings'] as List).first as Map)['localDate'] = '2026-02-30',
        (Map<String, dynamic> p) =>
            ((p['readings'] as List).first as Map)['offsetMinutes'] = 0,
        (Map<String, dynamic> p) =>
            ((p['readings'] as List).first as Map)['source'] = 'cloud',
        (Map<String, dynamic> p) =>
            ((p['readings'] as List).first as Map)['note'] = 'a' * 501,
        (Map<String, dynamic> p) =>
            ((p['readings'] as List).first as Map)['revision'] = -1,
        (Map<String, dynamic> p) => p['schemaVersion'] = 99,
        (Map<String, dynamic> p) =>
            p['readings'] = List.filled(100001, (p['readings'] as List).first),
      ]) {
        final p =
            jsonDecode(jsonEncode(archive.payload)) as Map<String, dynamic>;
        mutation(p);
        expect(() => BackupArchive.validate(p), throwsA(isA<BackupFailure>()));
      }
      final legacy =
          jsonDecode(jsonEncode(archive.payload)) as Map<String, dynamic>;
      legacy['schemaVersion'] = 1;
      ((legacy['readings'] as List).first as Map)
        ..remove('note')
        ..remove('originalCapturedAtUtc');
      (legacy['preferences'] as Map).remove('opaque');
      final migrated = BackupArchive.validate(legacy);
      expect(migrated.rows.single.note, '');
      expect(migrated.settings.opaque, isFalse);
      expect(migrated.payload['schemaVersion'], 2);
    },
  );
  test(
    'Snapshot completo senza filtri, sostituzione senza merge, stream aggiornati e pulizia',
    () async {
      await repo.save(sample(id: 'originale'));
      await repo.save(sample(id: 'altra'));
      final s = service();
      final snapshot = await s.snapshot();
      expect(snapshot.rows.length, 2);
      expect(snapshot.settings.reminders, [false, true, false]);
      final changes = <List<Measurement>>[];
      final subscription = repo.watch().listen(changes.add);
      await Future<void>.delayed(Duration.zero);
      List<bool>? applied;
      final result = await service(
        apply: (flags) async => applied = flags,
      ).replace(archive);
      expect(result.remindersPending, isFalse);
      expect(applied, [true, false, true]);
      expect((await repo.list()).map((m) => m.id), ['test']);
      await Future<void>.delayed(Duration.zero);
      expect(changes.last.single.id, 'test');
      expect(
        await db.customSelect('SELECT * FROM archive_operation').get(),
        isEmpty,
      );
      await subscription.cancel();
    },
  );
  for (final stage in ['prepared', 'afterDelete', 'beforeCommit']) {
    test('Rollback $stage mantiene archivio e preferenze originali', () async {
      await repo.save(sample(id: 'originale'));
      await SettingsRepository(
        db,
      ).save(const AppSettings(protectBackupWithPassword: true));
      final before = canonical((await service().snapshot()).payload);
      await expectLater(
        service(
          checkpoint: (at) async {
            if (at == stage) {
              throw const FileSystemException('spazio esaurito simulato');
            }
          },
        ).replace(archive),
        throwsA(isA<FileSystemException>()),
      );
      expect(canonical((await service().snapshot()).payload), before);
      expect(
        await db.customSelect('SELECT * FROM archive_operation').get(),
        isEmpty,
      );
    });
  }
  test(
    'Nuove scritture bloccate durante restore, nessun errore post-commit annulla i dati',
    () async {
      await repo.save(sample(id: 'originale'));
      final entered = Completer<void>(), release = Completer<void>();
      final restore = service(
        apply: (_) async => throw StateError('Android non disponibile'),
        checkpoint: (stage) async {
          if (stage == 'afterDelete') {
            entered.complete();
            await release.future;
          }
        },
      ).replace(archive);
      await entered.future;
      await expectLater(repo.save(sample(id: 'concorrenza')), throwsStateError);
      await expectLater(
        SettingsRepository(db).save(const AppSettings()),
        throwsStateError,
      );
      release.complete();
      final result = await restore;
      expect(result.remindersPending, isTrue);
      expect((await repo.list()).single.id, 'test');
      expect(
        (await db
                .customSelect('SELECT state FROM archive_operation')
                .getSingle())
            .read<String>('state'),
        'committed',
      );
      expect(await service().recover(), isTrue);
      expect((await repo.list()).single.id, 'test');
      expect(
        await db.customSelect('SELECT * FROM archive_operation').get(),
        isEmpty,
      );
    },
  );
  test(
    'Recupero su file cifrato dopo riapertura: prepared e committed distinti',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cardiograph-recovery-',
      );
      final file = File('${directory.path}/archive.sqlite');
      final vault = FakeVault();
      var local = await openArchive(file, vault);
      var r = MeasurementRepository(local);
      try {
        await r.save(sample(id: 'originale', note: 'RECOVERY_PRIVATE_TEXT'));
        final initial = BackupArchive(await r.list(), const AppSettings());
        final payload = canonical(initial.payload);
        await local.customStatement(
          "INSERT INTO archive_operation VALUES ('crash','prepared',?,?,?)",
          [payload, await payloadDigest(payload), payload],
        );
        await r.close();
        await local.close();
        expect(
          latin1.decode(file.readAsBytesSync()),
          isNot(contains('RECOVERY_PRIVATE_TEXT')),
        );
        local = await openArchive(file, vault);
        r = MeasurementRepository(local);
        expect((await r.list()).single.id, 'originale');
        expect(
          await local.customSelect('SELECT * FROM archive_operation').get(),
          isEmpty,
        );
        BackupService localService(bool fail) => BackupService(
          r,
          readReminders: () async => [false, false, false],
          applyReminders: (_) async {
            if (fail) throw StateError('temporaneo');
          },
          preferencesChanged: () {},
        );
        expect(
          (await localService(true).replace(archive)).remindersPending,
          isTrue,
        );
        await r.close();
        await local.close();
        local = await openArchive(file, vault);
        r = MeasurementRepository(local);
        expect((await r.list()).single.id, 'test');
        expect(await localService(false).recover(), isTrue);
        expect((await r.list()).single.id, 'test');
        expect(
          await local.customSelect('SELECT * FROM archive_operation').get(),
          isEmpty,
        );
      } finally {
        await r.close();
        await local.close();
        final resolved = await directory.resolveSymbolicLinks(),
            root = await Directory.systemTemp.resolveSymbolicLinks();
        if (!resolved.startsWith(
          '$root${Platform.pathSeparator}cardiograph-recovery-',
        )) {
          throw StateError('Percorso temporaneo inatteso');
        }
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Cancellazione transazionale distinta: letture e preferenze azzerate',
    () async {
      await repo.save(sample());
      await SettingsRepository(
        db,
      ).save(const AppSettings(protectBackupWithPassword: true, opaque: true));
      List<bool>? applied;
      await service(
        apply: (v) async => applied = v,
      ).replace(BackupArchive([], const AppSettings()), erase: true);
      expect(await repo.list(), isEmpty);
      expect(
        (await SettingsRepository(db).read()).protectBackupWithPassword,
        isFalse,
      );
      expect(applied, [false, false, false]);
    },
  );
  testWidgets(
    'Impostazioni: flag false e spiegazione della protezione facoltativa',
    (t) async {
      final files = CancelFiles();
      await db.customSelect('SELECT 1').get();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            measurementRepositoryProvider.overrideWith((ref) async => repo),
            backupServiceProvider.overrideWith((ref) async => service()),
            documentFileServiceProvider.overrideWithValue(files),
          ],
          child: MaterialApp(
            theme: appTheme(false),
            home: const GlassBackdrop(child: SettingsPage()),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('protect-backup')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('protect-backup')),
            )
            .value,
        isFalse,
      );
      expect(
        find.textContaining('leggibile da chi possiede il file'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'Footer bianco e fallback opaco, contrasti delle superfici composte',
    (t) async {
      final theme = appTheme(false);
      expect(theme.navigationBarTheme.indicatorColor, Colors.white);
      final active = theme.navigationBarTheme.iconTheme!.resolve({
        WidgetState.selected,
      });
      expect(active!.color, Brand.blue);
      for (final foreground in [Brand.navy, Brand.blue, Brand.red, Brand.ink]) {
        for (final background in [
          Colors.white,
          const Color(0xffe1eff8),
          const Color(0xffd5eafa),
        ]) {
          final ratio =
              (background.computeLuminance() + .05) /
              (foreground.computeLuminance() + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(true),
          home: const Scaffold(body: GlassCard(child: Text('Opaco'))),
        ),
      );
      final filters = t.widgetList<BackdropFilter>(find.byType(BackdropFilter));
      expect(filters.length, 1);
      final containers = t.widgetList<Container>(find.byType(Container));
      expect(
        containers.any(
          (w) =>
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.white,
        ),
        isTrue,
      );
    },
  );
}
