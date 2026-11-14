import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:cardiograph/core/services/contracts.dart';
import 'package:cardiograph/core/services/photo_services.dart';
import 'package:cardiograph/core/vision/seven_segment.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/data/app_database.dart';
import 'package:cardiograph/data/providers.dart';
import 'package:cardiograph/data/repositories.dart';
import 'package:cardiograph/features/measurements/camera_page.dart';
import 'package:cardiograph/features/measurements/photo_review.dart';
import 'package:cardiograph/features/measurements/manual_editor.dart';

class DelayedOcr implements OcrService {
  final completer = Completer<OcrCandidate>();
  @override
  Future<OcrCandidate> recognize(CapturedImage image, {DisplayCrop? crop}) =>
      completer.future;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  const channel = MethodChannel('dev.danking.cardiograph/camera');
  testWidgets('Permesso negato/permanente: recupero e alternativa manuale', (
    t,
  ) async {
    var requested = 0, settings = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestPermission') {
            requested++;
            return requested == 1 ? 'denied' : 'permanent';
          }
          if (call.method == 'settings') settings++;
          return null;
        });
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: appTheme(false), home: const CameraPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(requested, 1);
    expect(
      t
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Scatta'),
                  matching: find.byWidgetPredicate((w) => w is FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await t.tap(find.text('Consenti fotocamera'));
    await t.pumpAndSettle();
    expect(find.text('Apri impostazioni'), findsOneWidget);
    await t.tap(find.text('Apri impostazioni'));
    await t.pumpAndSettle();
    expect(settings, 1);
    expect(find.text('Inserisci a mano'), findsOneWidget);
    final semantics = t.ensureSemantics();
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
  testWidgets(
    'Revisione obbligatoria, OCR lento, stesso istante e source camera post commit',
    (t) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      final service = DelayedOcr();
      final instant = DateTime.utc(2026, 11, 14, 10, 34, 56, 789);
      final photo = CapturedImage(
        File('assets/logo.png').absolute.path,
        instant,
        zone: 'Europe/Rome',
        offsetMinutes: 60,
        precise: true,
        timestampSource: 'REALTIME',
        width: 1080,
        height: 2340,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => Scaffold(
              body: TextButton(
                onPressed: () => c.push('/photo'),
                child: const Text('Apri revisione'),
              ),
            ),
          ),
          GoRoute(path: '/photo', builder: (c, s) => PhotoReviewPage(photo)),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            ocrServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(
            theme: appTheme(false),
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Apri revisione'));
      await t.pump();
      await t.pump(const Duration(minutes: 2));
      expect(await MeasurementRepository(db).list(), isEmpty);
      service.completer.complete(
        const OcrCandidate(systolic: 123, diastolic: 88, pulse: 64),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Conferma e salva'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('11:34:56'), findsOneWidget);
      expect(await MeasurementRepository(db).list(), isEmpty);
      await t.tap(find.text('Conferma e salva'));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      final row = (await MeasurementRepository(db).list()).single;
      expect(row.measuredAtUtc, instant);
      expect(row.originalCapturedAtUtc, instant);
      expect(row.source, 'camera');
      expect(row.localTime, '11:34:56');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      router.dispose();
      await db.close();
    },
  );
  testWidgets('UNKNOWN non viene accettato come istante sensore preciso', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    final photo = CapturedImage(
      'unused',
      DateTime.utc(2026, 11, 14, 10),
      zone: 'Europe/Rome',
      offsetMinutes: 60,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: MaterialApp(
          theme: appTheme(false),
          home: ManualEditor(
            photo: photo,
            candidate: const OcrCandidate(
              systolic: 123,
              diastolic: 88,
              pulse: 64,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Conferma e salva'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Conferma e salva'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Verifica e conferma la data e l’ora'),
      findsOneWidget,
    );
    expect(await MeasurementRepository(db).list(), isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await db.close();
  });
  test(
    'Cache privata: eliminazione ripetibile e rifiuto file esterni',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cardiograph-photo-test-',
      );
      final owned = Directory('${directory.path}/cardiograph_camera');
      await owned.create();
      final store = TemporaryPhotoStore(owned);
      try {
        for (final outcome in ['salvata', 'annullata', 'ripetuta']) {
          final photo = File('${owned.path}/frame_$outcome.jpg');
          await photo.writeAsString('private');
          await store.delete(photo.path);
          expect(await photo.exists(), false);
          await store.delete(photo.path);
        }
        final external = File('${directory.path}/frame_external.jpg');
        await external.writeAsString('keep');
        await expectLater(
          store.delete(external.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await external.readAsString(), 'keep');
      } finally {
        final target = await directory.resolveSymbolicLinks();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        if (!target.startsWith(
          '$root${Platform.pathSeparator}cardiograph-photo-test-',
        )) {
          throw StateError('Unexpected path');
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );
}
