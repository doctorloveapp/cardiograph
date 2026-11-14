import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardiograph/app/app.dart';
import 'package:cardiograph/core/design_system/components.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:drift/native.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  late AppDatabase db;
  setUpAll(tzdata.initializeTimeZones);
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.danking.cardiograph/camera'),
          (call) async =>
              call.method == 'requestPermission' || call.method == 'permission'
              ? 'denied'
              : null,
        );
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() async {
    await db.close();
  });
  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async => db),
      zoneLookupProvider.overrideWithValue(() async => 'Europe/Rome'),
    ],
    child: const CardioGraphApp(),
  );
  testWidgets('Navigazione, scelta metodo e impostazioni', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Apri diario'), findsOneWidget);
    for (final label in ['Andamento', 'Calendario', 'Report', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Nuova misurazione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scatta foto'));
    await tester.pumpAndSettle();
    expect(find.text('Inquadra i tre valori'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuova misurazione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inserisci a mano'));
    await tester.pumpAndSettle();
    expect(find.text('Dati della misurazione'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Valori grandi e testo al 200 percento', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: MeasurementValue(
              label: 'Massima',
              unit: 'mmHg',
              value: 136,
              elevated: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('136'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Tocchi e semantica accessibili', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
