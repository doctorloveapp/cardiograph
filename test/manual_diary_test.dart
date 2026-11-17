import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/app/providers.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/core/services/contracts.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/features/measurements/manual_editor.dart';
import 'package:cardiograph/features/measurements/diary.dart';
import 'package:cardiograph/features/measurements/measurement.dart';

class FixedClock implements AppClock {
  final DateTime time;
  const FixedClock(this.time);
  @override
  DateTime now() => time;
}

class FailingRepository extends MeasurementRepository {
  FailingRepository(super.db);
  @override
  Future<void> save(Measurement m, {bool editing = false}) async =>
      throw const FileSystemException('disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUpAll(tzdata.initializeTimeZones);
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.danking.cardiograph/camera'),
          (call) async =>
              call.method == 'permission' || call.method == 'requestPermission'
              ? 'denied'
              : null,
        );
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() async => db.close());
  Widget app({bool failing = false, DateTime? now, Widget? home}) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          zoneLookupProvider.overrideWithValue(() async => 'Europe/Rome'),
          clockProvider.overrideWithValue(
            FixedClock(now ?? DateTime.utc(2026, 11, 14, 12, 30, 45)),
          ),
          if (failing)
            measurementRepositoryProvider.overrideWith(
              (ref) async => FailingRepository(db),
            ),
        ],
        child: home == null
            ? const CardioGraphApp()
            : MaterialApp(theme: appTheme(false), home: home),
      );
  Future<void> editor(
    WidgetTester t, {
    bool failing = false,
    DateTime? now,
  }) async {
    await t.pumpWidget(app(failing: failing, now: now));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Nuova misurazione'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nuova misurazione'));
    await t.pumpAndSettle();
    await t.tap(find.text('Inserisci a mano'));
    await t.pumpAndSettle();
  }

  Future<void> values(
    WidgetTester t, {
    String sys = '136',
    String dia = '90',
    String pulse = '100',
  }) async {
    for (final entry in [sys, dia, pulse].asMap().entries) {
      await t.enterText(
        find.byKey(ValueKey('reading-${entry.key}')),
        entry.value,
      );
    }
  }

  Future<void> save(WidgetTester t) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Salva misurazione'));
    await t.pumpAndSettle();
    await t.tap(find.text('Salva misurazione'));
    // A pending confirmation intentionally keeps the saving indicator active.
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Data congelata, validazione, commit e soglie indipendenti', (
    t,
  ) async {
    await editor(t);
    expect(find.text('12:30:45'), findsOneWidget);
    await save(t);
    expect(find.text('Inserisci un intero da 1 a 999'), findsNWidgets(3));
    await values(t);
    await save(t);
    final rows = await MeasurementRepository(db).list();
    expect(rows.length, 1);
    expect(rows.single.localTime, '12:30:45');
    expect(rows.single.systolic, 136);
    expect(find.text('Misurazione salvata'), findsOneWidget);
    expect(find.textContaining('Oltre soglia'), findsNothing);
    expect(
      t.widget<Text>(find.text('136')).style!.color,
      const Color(0xfff59e0b),
    );
  });
  testWidgets('Errore I/O mantiene tutti i campi e non mostra conferma', (
    t,
  ) async {
    await editor(t, failing: true);
    await values(t, sys: '123', dia: '88', pulse: '64');
    await save(t);
    expect(find.textContaining('Salvataggio non riuscito'), findsOneWidget);
    expect(find.text('Misurazione salvata'), findsNothing);
    for (final value in ['123', '88', '64']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(await MeasurementRepository(db).list(), isEmpty);
  });
  testWidgets('Tasto Avanti passa dalla massima alla minima senza saltarla', (
    t,
  ) async {
    await editor(t);
    await t.tap(find.byKey(const ValueKey('reading-0')));
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();
    final field = find.descendant(
      of: find.byKey(const ValueKey('reading-1')),
      matching: find.byType(EditableText),
    );
    expect(t.widget<EditableText>(field).focusNode.hasFocus, isTrue);
  });
  testWidgets('Massima <= minima richiede conferma e non scambia campi', (
    t,
  ) async {
    await editor(t);
    await values(t, sys: '80', dia: '90', pulse: '64');
    await save(t);
    expect(find.text('Verifica massima e minima'), findsOneWidget);
    await t.tap(find.text('Rivedi'));
    await t.pumpAndSettle();
    expect(await MeasurementRepository(db).list(), isEmpty);
    await save(t);
    await t.tap(find.text('Conferma'));
    await t.pumpAndSettle();
    final m = (await MeasurementRepository(db).list()).single;
    expect(m.systolic, 80);
    expect(m.diastolic, 90);
  });
  testWidgets('Uscita con modifiche e doppione morbido', (t) async {
    await editor(t);
    await values(t, sys: '123', dia: '88', pulse: '64');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('Uscire senza salvare?'), findsOneWidget);
    await t.tap(find.text('Rivedi'));
    await t.pumpAndSettle();
    await save(t);
    await t.ensureVisible(find.text('Nuova misurazione'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nuova misurazione'));
    await t.pumpAndSettle();
    await t.tap(find.text('Inserisci a mano'));
    await t.pumpAndSettle();
    await values(t, sys: '123', dia: '88', pulse: '64');
    await save(t);
    expect(find.text('Possibile doppione'), findsOneWidget);
    await t.tap(find.text('Salva comunque'));
    await t.pumpAndSettle();
    expect((await MeasurementRepository(db).list()).length, 2);
  });
  testWidgets('DST gap e fold non vengono normalizzati silenziosamente', (
    t,
  ) async {
    await editor(t, now: DateTime.utc(2026, 3, 29, 2, 30));
    await values(t);
    await save(t);
    expect(find.textContaining('Questo orario non esiste'), findsOneWidget);
    expect(await MeasurementRepository(db).list(), isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await editor(t, now: DateTime.utc(2026, 10, 25, 2, 30));
    await values(t);
    await save(t);
    expect(find.text('Orario ripetuto: scegli l’offset'), findsOneWidget);
    expect(find.textContaining('UTC+02:00'), findsOneWidget);
    expect(find.textContaining('UTC+01:00'), findsOneWidget);
    expect(await MeasurementRepository(db).list(), isEmpty);
  });
  testWidgets('Nota 500, tastiera, 3 cifre e scala 200% senza overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(1200, 2550);
    t.view.devicePixelRatio = 3;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = t.ensureSemantics();
    await editor(t);
    await values(t);
    await t.scrollUntilVisible(
      find.text('Nota facoltativa'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ManualEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Nota facoltativa'));
    await t.pumpAndSettle();
    final note = find.byKey(const ValueKey('note'));
    await t.ensureVisible(note);
    await t.enterText(note, List.filled(500, 'a').join());
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    expect(t.takeException(), isNull);
    expect(t.widget<TextFormField>(note).controller!.text.length, 500);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
  testWidgets('Diario con nota 500 e cifre 999 leggibile al 200%', (t) async {
    final now = DateTime.utc(2026, 11, 14, 11, 30);
    final note = List.filled(500, 'a').join();
    final repo = MeasurementRepository(db);
    await repo.save(
      Measurement(
        id: 'large',
        systolic: 999,
        diastolic: 999,
        pulse: 999,
        measuredAtUtc: now,
        zone: 'Europe/Rome',
        offsetMinutes: 60,
        localDate: '2026-11-14',
        localTime: '12:30:00',
        note: note,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    await repo.close();
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = t.ensureSemantics();
    await t.pumpWidget(app(home: const DiaryPage()));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text(note),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(note), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
  testWidgets('Modifica, eliminazione e Annulla aggiornano Home e diario', (
    t,
  ) async {
    await editor(t);
    await values(t, sys: '123', dia: '88', pulse: '64');
    await save(t);
    await t.tap(find.text('Apri diario'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Apri lettura'));
    await t.tap(find.text('Apri lettura'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Modifica lettura'));
    await t.tap(find.text('Modifica lettura'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('reading-0')), '124');
    await save(t);
    expect((await MeasurementRepository(db).list()).single.systolic, 124);
    await t.ensureVisible(find.text('Elimina lettura'));
    await t.tap(find.text('Elimina lettura'));
    await t.pumpAndSettle();
    expect(await MeasurementRepository(db).list(), isEmpty);
    await t.tap(find.text('Annulla'));
    await t.pumpAndSettle();
    expect((await MeasurementRepository(db).list()).single.systolic, 124);
    expect(find.text('124'), findsOneWidget);
  });
  testWidgets('Data futura richiede conferma prima del commit', (t) async {
    final when = DateTime.utc(2099, 11, 14, 11, 30);
    final m = Measurement(
      id: 'future',
      systolic: 123,
      diastolic: 88,
      pulse: 64,
      measuredAtUtc: when,
      zone: 'Europe/Rome',
      offsetMinutes: 60,
      localDate: '2099-11-14',
      localTime: '12:30:00',
      createdAtUtc: when,
      updatedAtUtc: when,
    );
    await t.pumpWidget(app(home: ManualEditor(initial: m)));
    await t.pumpAndSettle();
    await save(t);
    expect(find.text('Data futura'), findsOneWidget);
    expect(await MeasurementRepository(db).list(), isEmpty);
    await t.tap(find.text('Rivedi'));
    await t.pumpAndSettle();
    expect(find.text('123'), findsOneWidget);
  });
}
