import 'dart:async';
import 'package:drift/drift.dart';
import '../features/measurements/measurement.dart';
import '../core/time/measurement_time.dart';
import 'app_database.dart';
import 'calendar_summary.dart';

List<Variable> sqlVariables(Iterable<Object?> values) => values
    .map<Variable>(
      (v) => v is String ? Variable<String>(v) : Variable<int>(v as int?),
    )
    .toList();

class MeasurementDao {
  final AppDatabase db;
  MeasurementDao(this.db);
  Future<List<Measurement>> list({CivilPeriod? period}) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM measurements ${period == null ? '' : 'WHERE local_date >= ? AND local_date <= ?'} ORDER BY measured_at_utc DESC, id ASC',
          variables: period == null
              ? []
              : sqlVariables([period.start, period.end]),
        )
        .get();
    return rows.map((r) => Measurement.fromRow(r.data)).toList();
  }

  Future<Measurement?> get(String id) async {
    final row = await db
        .customSelect(
          'SELECT * FROM measurements WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    return row == null ? null : Measurement.fromRow(row.data);
  }
}

class MeasurementRepository {
  final AppDatabase db;
  late final dao = MeasurementDao(db);
  final _changes = StreamController<void>.broadcast(sync: true);
  MeasurementRepository(this.db);
  Future<List<Measurement>> list({CivilPeriod? period}) =>
      dao.list(period: period);
  Stream<List<Measurement>> watch({CivilPeriod? period}) =>
      watchQuery(() => list(period: period));
  Stream<T> watchQuery<T>(Future<T> Function() read) => Stream.multi((sink) {
    var canceled = false;
    Future<void> queue = Future.value();
    void refresh() {
      queue = queue.then((_) async {
        try {
          final rows = await read();
          if (!canceled) sink.add(rows);
        } catch (e, st) {
          if (!canceled) sink.addError(e, st);
        }
      });
    }

    final sub = _changes.stream.listen((_) => refresh());
    sink.onCancel = () {
      canceled = true;
      return sub.cancel();
    };
    refresh();
  });

  /// One indexed GROUP BY for the visible month, never a query per cell.
  Future<Map<String, CalendarDaySummary>> monthSummary(String month) async {
    final first = DateTime.parse('$month-01');
    final end = DateTime.utc(first.year, first.month + 1, 0);
    final rows = await db.customSelect(
      '''SELECT local_date, COUNT(*) AS n,
      SUM(CASE WHEN local_time >= '07:00:00' AND local_time < '13:01:00' THEN 1 ELSE 0 END) AS morning,
      SUM(CASE WHEN local_time >= '13:01:00' AND local_time < '19:01:00' THEN 1 ELSE 0 END) AS afternoon,
      SUM(CASE WHEN local_time < '07:00:00' OR local_time >= '19:01:00' THEN 1 ELSE 0 END) AS evening,
      SUM(CASE WHEN systolic > 135 OR diastolic > 90 OR pulse > 100 THEN 1 ELSE 0 END) AS high_count
      FROM measurements WHERE local_date >= ? AND local_date <= ? GROUP BY local_date''',
      variables: sqlVariables(['$month-01', dateKey(end)]),
    ).get();
    return {
      for (final r in rows)
        r.read<String>('local_date'): CalendarDaySummary(
          r.read('local_date'),
          r.read('n'),
          r.read('morning'),
          r.read('afternoon'),
          r.read('evening'),
          r.read('high_count'),
        ),
    };
  }

  Stream<Map<String, CalendarDaySummary>> watchMonth(String month) =>
      watchQuery(() => monthSummary(month));
  Future<void> save(Measurement m, {bool editing = false}) async {
    m.validate();
    await db.transaction(() async {
      if (editing) {
        final values = Map<String, Object?>.from(m.values)..remove('id');
        final changed = await db.customUpdate(
          'UPDATE measurements SET ${values.keys.map((k) => '$k = ?').join(',')} WHERE id = ? AND revision = ?',
          variables: sqlVariables([...values.values, m.id, m.revision - 1]),
        );
        if (changed != 1) {
          throw StateError(
            'La lettura è stata modificata. Riaprila dal diario.',
          );
        }
      } else {
        final previous = await dao.get(m.id);
        if (previous != null) {
          if (previous.systolic != m.systolic ||
              previous.diastolic != m.diastolic ||
              previous.pulse != m.pulse ||
              previous.measuredAtUtc != m.measuredAtUtc ||
              previous.note != m.note) {
            throw StateError(
              'Questa lettura risulta già salvata. Controlla il diario.',
            );
          }
          return;
        }
        await db.customStatement(
          'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
          m.values.values.toList(),
        );
      }
    });
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> possibleDuplicate(Measurement m) async {
    final rows = await db
        .customSelect(
          'SELECT id FROM measurements WHERE id != ? AND systolic = ? AND diastolic = ? AND pulse = ? AND measured_at_utc BETWEEN ? AND ? LIMIT 1',
          variables: sqlVariables([
            m.id,
            m.systolic,
            m.diastolic,
            m.pulse,
            m.measuredAtUtc.millisecondsSinceEpoch - 120000,
            m.measuredAtUtc.millisecondsSinceEpoch + 120000,
          ]),
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<void> delete(Measurement m) async {
    await db.transaction(() async {
      final count = await db.customUpdate(
        'DELETE FROM measurements WHERE id = ? AND revision = ?',
        variables: sqlVariables([m.id, m.revision]),
      );
      if (count != 1) {
        throw StateError('Lettura modificata: ricarica il diario.');
      }
    });
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> restore(Measurement m) => save(m);
  Future<void> close() => _changes.close();
}

class AppSettings {
  final bool protectBackupWithPassword;
  const AppSettings({this.protectBackupWithPassword = false});
}

class SettingsRepository {
  final AppDatabase db;
  const SettingsRepository(this.db);
  Future<AppSettings> read() async {
    final row = await db
        .customSelect(
          'SELECT protect_backup_with_password FROM app_settings WHERE id = 1',
        )
        .getSingle();
    return AppSettings(
      protectBackupWithPassword:
          row.read<int>('protect_backup_with_password') == 1,
    );
  }

  Future<void> save(AppSettings settings) => db.transaction(
    () => db.customStatement(
      'UPDATE app_settings SET protect_backup_with_password = ? WHERE id = 1',
      [settings.protectBackupWithPassword ? 1 : 0],
    ),
  );
}
