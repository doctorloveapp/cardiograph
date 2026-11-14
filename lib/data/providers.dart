import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../features/measurements/measurement.dart';
import 'app_database.dart';
import 'repositories.dart';
import 'calendar_summary.dart';
import '../core/time/measurement_time.dart';

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await openDeviceArchive();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});
final measurementRepositoryProvider = FutureProvider<MeasurementRepository>((
  ref,
) async {
  final repository = MeasurementRepository(
    await ref.watch(databaseProvider.future),
  );
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});
final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) async => SettingsRepository(await ref.watch(databaseProvider.future)),
);
final measurementsProvider = StreamProvider<List<Measurement>>((ref) async* {
  final repo = await ref.watch(measurementRepositoryProvider.future);
  yield* repo.watch();
});
final zoneLookupProvider = Provider<Future<String> Function()>(
  (ref) =>
      () async => (await FlutterTimezone.getLocalTimezone()).identifier,
);
final monthSummaryProvider = StreamProvider.autoDispose
    .family<Map<String, CalendarDaySummary>, String>((ref, month) async* {
      final repo = await ref.watch(measurementRepositoryProvider.future);
      yield* repo.watchMonth(month);
    });
final dayReadingsProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, day) async* {
      final repo = await ref.watch(measurementRepositoryProvider.future);
      yield* repo.watch(period: CivilPeriod(day, day));
    });
final periodReadingsProvider = StreamProvider.autoDispose
    .family<List<Measurement>, (String, String)>((ref, period) async* {
      final repo = await ref.watch(measurementRepositoryProvider.future);
      yield* repo.watch(period: CivilPeriod(period.$1, period.$2));
    });
