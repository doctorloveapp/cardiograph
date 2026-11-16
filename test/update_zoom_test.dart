import 'package:cardiograph/core/services/platform_services.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cardiograph/core/design_system/theme.dart';
import 'package:cardiograph/core/services/export_names.dart';
import 'package:cardiograph/features/analytics/zoom_chart_card.dart';
import 'package:cardiograph/features/settings/updates_page.dart';

void main() {
  testWidgets(
    'Aggiornamenti: default true, switch persistito e apertura release',
    (t) async {
      var automatic = true, opened = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidDocumentFileService.channel, (
            call,
          ) async {
            if (call.method == 'autoUpdates') return automatic;
            if (call.method == 'setAutoUpdates') {
              automatic = (call.arguments as Map)['enabled'] as bool;
            }
            if (call.method == 'openReleases') opened = true;
            return null;
          });
      await t.pumpWidget(
        MaterialApp(theme: appTheme(false), home: const UpdatesPage()),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(automatic, isFalse);
      expect(await autoUpdatesEnabled(), isFalse);
      await t.tap(find.text('Ultima release'));
      await t.pumpAndSettle();
      expect(opened, isTrue);
      await t.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidDocumentFileService.channel, null);
    },
  );
  test('Release: confronto numerico, tag/asset esatti, niente prerelease', () {
    Map<String, Object> release(String v) => {
      'tag_name': 'CardioGraphVer$v',
      'draft': false,
      'prerelease': false,
      'assets': [
        {'name': 'CardioGraph.Ver$v.apk', 'state': 'uploaded'},
      ],
    };
    expect(availableRelease(release('1.10.0'), '1.4.0'), '1.10.0');
    expect(availableRelease(release('1.4.0'), '1.4.0'), isNull);
    expect(availableRelease(release('1.3.1'), '1.4.0'), isNull);
    expect(
      availableRelease({...release('2.0.0'), 'prerelease': true}, '1.4.0'),
      isNull,
    );
    expect(
      availableRelease({...release('2.0.0'), 'assets': []}, '1.4.0'),
      isNull,
    );
    expect(availableRelease(release('2.0.0-beta'), '1.4.0'), isNull);
  });
  test('Offline e flag false non bloccano e non inviano richieste', () async {
    var count = 0;
    Future<Object?> load() async {
      count++;
      throw const SocketException('offline');
    }

    expect(await checkForUpdate(enabled: false, load: load), isNull);
    expect(count, 0);
    expect(await checkForUpdate(enabled: true, load: load), isNull);
    expect(count, 1);
  });
  test('Nomi backup e PDF con date DD_MM_AAAA e minuti locali', () {
    expect(
      backupFilename(DateTime(2026, 11, 16, 9, 4)),
      'CardioGraph_16_11_2026_09_04.cardiograph',
    );
    expect(
      reportFilename('2026-01-02', '2026-11-16'),
      'CardioGraph_02_01_2026_16_11_2026.pdf',
    );
  });
  Widget harness({void Function(FlTouchEvent, LineTouchResponse?)? touch}) =>
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              return _ChartHarness(touch: touch);
            },
          ),
        ),
      );
  testWidgets('2X pan due assi: pagina ferma, header/reset fissi, ritorno 1X', (
    t,
  ) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    final header = find.text('Pressione');
    final button = find.byKey(const ValueKey('chart-zoom-toggle'));
    final headerPosition = t.getTopLeft(header),
        buttonPosition = t.getTopLeft(button);
    final initial = t.widget<LineChart>(find.byType(LineChart)).data;
    await t.tap(button);
    await t.pumpAndSettle();
    final controller = t
        .widget<LineChart>(find.byType(LineChart))
        .transformationConfig
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), 2);
    final before = controller.value.getTranslation();
    await t.drag(find.byType(LineChart), const Offset(-35, -30));
    await t.pumpAndSettle();
    final moved = controller.value.getTranslation();
    expect(moved.x, lessThan(before.x));
    expect(moved.y, lessThan(before.y));
    final scroll = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(scroll.pixels, 0);
    expect(t.getTopLeft(header), headerPosition);
    expect(t.getTopLeft(button), buttonPosition);
    await t.drag(find.byType(LineChart), const Offset(25, 25));
    await t.pumpAndSettle();
    expect(controller.value.getTranslation().x, greaterThan(moved.x));
    expect(controller.value.getTranslation().y, greaterThan(moved.y));
    await t.tap(button);
    await t.pumpAndSettle();
    expect(controller.value, Matrix4.identity());
    final finalData = t.widget<LineChart>(find.byType(LineChart)).data;
    expect(
      finalData.lineBarsData.first.spots,
      initial.lineBarsData.first.spots,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('Tap della misura resta corretto in 2X e dopo trascinamento', (
    t,
  ) async {
    final selected = <int>[];
    await t.pumpWidget(
      harness(
        touch: (event, response) {
          if (event is FlTapUpEvent &&
              response?.lineBarSpots?.isNotEmpty == true) {
            selected.add(response!.lineBarSpots!.first.spotIndex);
          }
        },
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('chart-zoom-toggle')));
    await t.pumpAndSettle();
    final center = t.getCenter(find.byType(LineChart));
    await t.tapAt(center);
    await t.pumpAndSettle();
    expect(selected.last, 1);
    await t.dragFrom(center, const Offset(-25, -25));
    await t.pumpAndSettle();
    await t.tapAt(center - const Offset(25, 25));
    await t.pumpAndSettle();
    expect(selected.last, 1);
    expect(selected.length, 2);
    expect(t.takeException(), isNull);
  });
}

class _ChartHarness extends StatefulWidget {
  final void Function(FlTouchEvent, LineTouchResponse?)? touch;
  const _ChartHarness({this.touch});
  @override
  State<_ChartHarness> createState() => _ChartHarnessState();
}

class _ChartHarnessState extends State<_ChartHarness> {
  final locked = ValueNotifier<bool>(false);
  @override
  void dispose() {
    locked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    physics: ChartScrollPhysics(locked),
    children: [
      const SizedBox(height: 50),
      ZoomChartCard(
        title: 'Pressione',
        legend: const Text('Massima / Minima'),
        onInteraction: (value) => locked.value = value,
        data: LineChartData(
          minX: 0,
          maxX: 10,
          minY: 0,
          maxY: 10,
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              isCurved: false,
              spots: const [FlSpot(2, 2), FlSpot(5, 5), FlSpot(8, 8)],
            ),
          ],
          lineTouchData: LineTouchData(touchCallback: widget.touch),
        ),
      ),
      const SizedBox(height: 1000),
    ],
  );
}
