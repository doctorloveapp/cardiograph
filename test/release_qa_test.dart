import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/features/backup/backup_settings.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:cardiograph/app/version.dart';
import 'package:cardiograph/features/settings/about_page.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/repositories.dart';
import 'repository_test.dart' show sample;

void main() {
  testWidgets('Archivio occupato al resume non segnala un restore fallito', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    db.maintenance = true;
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CardioGraphApp(),
      ),
    );
    await t.pumpAndSettle();
    expect(container.read(recoveryWarningProvider), isFalse);
    await t.pumpWidget(const SizedBox());
    container.dispose();
    db.maintenance = false;
    await db.close();
  });
  test(
    'Versione pubblica unica 1.2.2 build 4, nessun suffisso di sviluppo',
    () {
      expect(AppVersion.name, '1.2.2');
      expect(AppVersion.build, 4);
      expect(AppVersion.label, 'CardioGraph 1.2.2 (build 4)');
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('version: 1.2.2+4'),
      );
      for (final p in [
        'README.md',
        'lib/features/settings/settings_page.dart',
        'lib/features/backup/backup_codec.dart',
      ]) {
        expect(File(p).readAsStringSync(), isNot(contains('-dev')));
      }
    },
  );
  testWidgets('Informazioni e guida al 200%, navigazione e testo accessibili', (
    t,
  ) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      MaterialApp(theme: appTheme(true), home: const AboutPage()),
    );
    expect(find.text(AppVersion.label), findsOneWidget);
    expect(find.text('Dan King'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await t.drag(find.byType(ListView), const Offset(0, -500));
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });
  test(
    'Migrazione v2 → v4 conserva letture e flag true senza sovrascrittura',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cardiograph-release-migration-',
      );
      final file = File('${directory.path}/test.sqlite');
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(measurementV1);
      raw.execute(
        "ALTER TABLE measurements ADD COLUMN note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=500)",
      );
      raw.execute(
        'CREATE TABLE app_settings(id INTEGER PRIMARY KEY,protect_backup_with_password INTEGER NOT NULL DEFAULT 0)',
      );
      raw.execute('INSERT INTO app_settings VALUES(1,1)');
      final m = sample(note: 'Nota di migrazione: attività e caffè');
      raw.execute(
        'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
        m.values.values.toList(),
      );
      raw.execute('PRAGMA user_version=2');
      raw.close();
      final db = AppDatabase(NativeDatabase(file));
      final repo = MeasurementRepository(db);
      try {
        expect((await repo.list()).single.values, m.values);
        expect(
          (await SettingsRepository(db).read()).protectBackupWithPassword,
          isTrue,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          4,
        );
      } finally {
        await repo.close();
        await db.close();
        await file.delete();
        await directory.delete();
      }
    },
  );
}
