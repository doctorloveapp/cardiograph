import '../core/health_ranges.dart';
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
  final Future<void> Function()? beforeMutation, afterMutation;
  MeasurementRepository(this.db, {this.beforeMutation, this.afterMutation});
  Future<T> _mutate<T>(Future<T> Function() action) => db.write(() async {
    // A durable unknown marker prevents a stale coverage snapshot from notifying
    // if the process dies between the DB commit and the Android mirror update.
    await beforeMutation?.call();
    try {
      return await action();
    } finally {
      try {
        await afterMutation?.call();
      } catch (_) {
        /* Keep marker; retry on resume. */
      }
    }
  });

  Future<Map<String, List<String>>> reminderCoverage() async {
    final rows = await db.customSelect("""SELECT DISTINCT
      CASE WHEN local_time >= '07:00:00' AND local_time < '13:01:00' THEN '1000'
      WHEN local_time >= '13:01:00' AND local_time < '19:01:00' THEN '1600'
      ELSE '2100' END AS slot,
      CASE WHEN local_time < '07:00:00' THEN date(local_date, '-1 day')
      ELSE local_date END AS anchor FROM measurements""").get();
    return {
      for (final id in ['1000', '1600', '2100'])
        id: rows
            .where((r) => r.read<String>('slot') == id)
            .map((r) => r.read<String>('anchor'))
            .toList(),
    };
  }

  Future<List<Measurement>> snapshotAll() =>
      db.transaction(() async => List.unmodifiable(await list()));
  Future<List<Measurement>> list({CivilPeriod? period}) =>
      dao.list(period: period);
  Future<List<Measurement>> snapshot(CivilPeriod period) => db.transaction(
    () async => List<Measurement>.unmodifiable(await list(period: period)),
  );
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
      SUM(CASE WHEN systolic >= 130 OR diastolic >= 85 THEN 1 ELSE 0 END) AS high_count,
      MAX(CASE WHEN systolic >=160 OR diastolic >=100 THEN 4
        WHEN systolic >=140 OR diastolic >=90 THEN 3
        WHEN systolic >=130 OR diastolic >=85 THEN 2
        WHEN systolic <90 OR diastolic <60 THEN 1 ELSE 0 END) AS range_priority
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
          PressureRange.values.firstWhere(
            (v) => v.priority == r.read<int>('range_priority'),
          ),
        ),
    };
  }

  Stream<Map<String, CalendarDaySummary>> watchMonth(String month) =>
      watchQuery(() => monthSummary(month));
  Future<void> save(Measurement m, {bool editing = false}) async {
    m.validate();
    await _mutate(
      () => db.transaction(() async {
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
      }),
    );
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
    await _mutate(
      () => db.transaction(() async {
        final count = await db.customUpdate(
          'DELETE FROM measurements WHERE id = ? AND revision = ?',
          variables: sqlVariables([m.id, m.revision]),
        );
        if (count != 1) {
          throw StateError('Lettura modificata: ricarica il diario.');
        }
      }),
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> restore(Measurement m) => save(m);
  Future<void> close() => _changes.close();
}

class AppSettings {
  final bool protectBackupWithPassword, opaque;
  final List<bool> reminders;
  final List<int> reminderMinutes;
  final DateTime? lastBackupUtc;
  const AppSettings({
    this.protectBackupWithPassword = false,
    this.opaque = false,
    this.reminders = const [false, false, false],
    this.reminderMinutes = const [600, 960, 1260],
    this.lastBackupUtc,
  });
  AppSettings copyWith({
    bool? protectBackupWithPassword,
    bool? opaque,
    List<bool>? reminders,
    List<int>? reminderMinutes,
    DateTime? lastBackupUtc,
  }) => AppSettings(
    protectBackupWithPassword:
        protectBackupWithPassword ?? this.protectBackupWithPassword,
    opaque: opaque ?? this.opaque,
    reminders: reminders ?? this.reminders,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    lastBackupUtc: lastBackupUtc ?? this.lastBackupUtc,
  );
  Map<String, Object> get portable => {
    'protectBackupWithPassword': protectBackupWithPassword,
    'reminderMinutes': reminderMinutes,
    'reminders': reminders,
  };
}

class SettingsRepository {
  final AppDatabase db;
  const SettingsRepository(this.db);
  Future<AppSettings> read() async {
    final r =
        (await db
                .customSelect('SELECT * FROM app_settings WHERE id=1')
                .getSingle())
            .data;
    return AppSettings(
      protectBackupWithPassword: r['protect_backup_with_password'] == 1,
      opaque: false,
      reminderMinutes: [
        for (final band in ['morning', 'afternoon', 'evening'])
          r['reminder_${band}_minutes'] as int,
      ],
      reminders: [
        r['reminder_morning'] == 1,
        r['reminder_afternoon'] == 1,
        r['reminder_evening'] == 1,
      ],
      lastBackupUtc: r['last_backup_utc'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              r['last_backup_utc'] as int,
              isUtc: true,
            ),
    );
  }

  Future<void> save(AppSettings settings) =>
      db.write(() => db.transaction(() => writeInsideTransaction(settings)));
  Future<void> update(AppSettings Function(AppSettings) change) => db.write(
    () => db.transaction(
      () async => writeInsideTransaction(change(await read())),
    ),
  );
  Future<void> writeInsideTransaction(AppSettings s) => db.customStatement(
    'UPDATE app_settings SET protect_backup_with_password=?,opaque=?,reminder_morning=?,reminder_afternoon=?,reminder_evening=?,reminder_morning_minutes=?,reminder_afternoon_minutes=?,reminder_evening_minutes=?,last_backup_utc=? WHERE id=1',
    [
      s.protectBackupWithPassword ? 1 : 0,
      0,
      ...s.reminders.map((v) => v ? 1 : 0),
      ...s.reminderMinutes,
      s.lastBackupUtc?.millisecondsSinceEpoch,
    ],
  );
}
