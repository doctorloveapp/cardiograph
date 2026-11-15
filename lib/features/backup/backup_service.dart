import '../reminders/reminder_sync.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/app_database.dart';
import '../../data/repositories.dart';
import '../../data/providers.dart';
import '../measurements/measurement.dart';
import 'backup_codec.dart';

Future<Uint8List> encodeBackupWorker((BackupArchive, String?, DateTime) r) =>
    encodeBackup(r.$1, passphrase: r.$2, now: r.$3);
bool backupNeedsPassword(Uint8List bytes) =>
    BackupEnvelope.inspect(bytes).encrypted;
Future<BackupArchive> decodeBackupWorker((Uint8List, String?) r) =>
    BackupEnvelope.inspect(r.$1).decode(passphrase: r.$2);
String serializeArchive(BackupArchive archive) =>
    canonical(BackupArchive.validate(archive.payload).payload);
BackupArchive parseArchive(String text) =>
    BackupArchive.validate(jsonDecode(text));

class RestoreOutcome {
  final bool remindersPending;
  const RestoreOutcome({this.remindersPending = false});
}

/// Repository writes are fenced for the complete operation; SQLite supplies the
/// crash-safe commit boundary. Staging/recovery are encrypted at rest by sqlite3mc.
class BackupService {
  final MeasurementRepository repository;
  final Future<List<bool>> Function() readReminders;
  final Future<void> Function(List<bool>) applyReminders;
  final void Function() preferencesChanged;
  final Future<void> Function(String stage)? checkpoint;
  BackupService(
    this.repository, {
    required this.readReminders,
    required this.applyReminders,
    required this.preferencesChanged,
    this.checkpoint,
  });
  AppDatabase get db => repository.db;
  SettingsRepository get settings => SettingsRepository(db);

  Future<BackupArchive> snapshot() => db.exclusive(() async {
    final reminders = await readReminders();
    return db.transaction(
      () async => BackupArchive(
        await repository.list(),
        (await settings.read()).copyWith(reminders: reminders),
      ),
    );
  });
  Future<void> markSuccessfulBackup(DateTime at) async {
    await settings.update((prefs) => prefs.copyWith(lastBackupUtc: at.toUtc()));
    preferencesChanged();
  }

  Future<bool> recover() async {
    if (db.maintenance) return false;
    return db.exclusive(_recoverInside);
  }

  Future<bool> _recoverInside() async {
    await db.recoverPrepared();
    final rows = await db
        .customSelect(
          "SELECT id FROM archive_operation WHERE state='committed'",
        )
        .get();
    if (rows.isEmpty) return true;
    try {
      await applyReminders((await settings.read()).reminders);
      await db.transaction(
        () => db.customStatement(
          "DELETE FROM archive_operation WHERE state='committed'",
        ),
      );
      preferencesChanged();
      return true;
    } catch (_) {
      return false;
    } // Data is already committed. Retry on next resume.
  }

  Future<RestoreOutcome> replace(
    BackupArchive archive, {
    bool erase = false,
  }) async {
    final staged = await compute(
      serializeArchive,
      archive,
    ); // All validation precedes the write fence.
    return db.exclusive(() async {
      if (!await _recoverInside()) {
        throw const BackupFailure(
          'Completa prima la riconciliazione dei promemoria e riprova',
        );
      }
      final current = await db.transaction(
        () async => BackupArchive(
          await repository.list(),
          (await settings.read()).copyWith(reminders: await readReminders()),
        ),
      );
      final oldLocalSettings = await settings.read();
      final recovery = await compute(serializeArchive, current);
      final digest = await payloadDigest(recovery), id = newMeasurementId();
      var committed = false;
      try {
        await db.transaction(
          () => db.customStatement(
            "INSERT INTO archive_operation(id,state,recovery,recovery_hash,staging) VALUES (?,'prepared',?,?,?)",
            [id, recovery, digest, staged],
          ),
        );
        final row = await db
            .customSelect(
              'SELECT * FROM archive_operation WHERE id=?',
              variables: sqlVariables([id]),
            )
            .getSingle();
        if (await payloadDigest(row.read<String>('recovery')) !=
            row.read<String>('recovery_hash')) {
          throw const BackupFailure('Copia di recupero non verificata');
        }
        final verifiedRecovery = await compute(
          parseArchive,
          row.read<String>('recovery'),
        );
        if (verifiedRecovery.rows.length != current.rows.length) {
          throw const BackupFailure('Copia di recupero incompleta');
        }
        final imported = await compute(
          parseArchive,
          row.read<String>('staging'),
        );
        await checkpoint?.call('prepared');
        await repository.beforeMutation?.call();
        await db.transaction(() async {
          await db.customStatement('DELETE FROM measurements');
          await checkpoint?.call('afterDelete');
          await db.batch((batch) {
            for (final m in imported.rows) {
              batch.customStatement(
                'INSERT INTO measurements (${m.values.keys.join(',')}) VALUES (${List.filled(m.values.length, '?').join(',')})',
                m.values.values.toList(),
              );
            }
          });
          await settings.writeInsideTransaction(
            erase
                ? const AppSettings()
                : imported.settings.copyWith(
                    lastBackupUtc: oldLocalSettings.lastBackupUtc,
                  ),
          );
          final count =
              (await db
                      .customSelect('SELECT COUNT(*) AS n FROM measurements')
                      .getSingle())
                  .read<int>('n');
          final integrity =
              (await db.customSelect('PRAGMA quick_check').getSingle())
                  .read<String>('quick_check');
          if (count != imported.rows.length || integrity != 'ok') {
            throw const BackupFailure('Verifica archivio non riuscita');
          }
          // Verify full persisted records, not just their count.
          final written = BackupArchive(
            await repository.list(),
            imported.settings,
          );
          if (await compute(serializeArchive, written) != staged) {
            throw const BackupFailure('Dati importati non corrispondenti');
          }
          await db.customStatement(
            "UPDATE archive_operation SET state='committed' WHERE id=?",
            [id],
          );
          await checkpoint?.call('beforeCommit');
        });
        committed = true;
        repository.notifyChanged();
        preferencesChanged();
        return RestoreOutcome(remindersPending: !await _recoverInside());
      } finally {
        if (!committed) {
          try {
            await repository.afterMutation?.call();
          } catch (_) {
            /* Resume retries. */
          }
          // A crash here leaves a prepared row, cleaned on next open; active rows
          // have already been rolled back by SQLite. Never restore over a commit.
          await db.transaction(
            () => db.customStatement(
              "DELETE FROM archive_operation WHERE id=? AND state='prepared'",
              [id],
            ),
          );
        }
      }
    });
  }

  Future<void> setReminder(int id, bool enabled) => db.exclusive(() async {
    final reminders = await readReminders();
    final index = [1000, 1600, 2100].indexOf(id);
    if (index < 0) throw ArgumentError('Promemoria non valido');
    reminders[index] = enabled;
    final prefs = (await settings.read()).copyWith(reminders: reminders);
    await repository.beforeMutation?.call();
    await db.transaction(() => settings.writeInsideTransaction(prefs));
    await applyReminders(reminders);
    preferencesChanged();
  });
  Future<void> setReminderTime(int id, int minutes) => db.exclusive(() async {
    final index = reminderIds.indexOf(id);
    if (index < 0 || !validReminderMinute(index, minutes)) {
      throw ArgumentError('Orario fuori dalla fascia selezionata');
    }
    final current = await settings.read();
    final times = current.reminderMinutes.toList()..[index] = minutes;
    await repository.beforeMutation?.call();
    await db.transaction(
      () => settings.writeInsideTransaction(
        current.copyWith(reminderMinutes: times),
      ),
    );
    await applyReminders(current.reminders);
    preferencesChanged();
  });
}

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final repository = await ref.watch(measurementRepositoryProvider.future);
  return BackupService(
    repository,
    readReminders: () async =>
        (await SettingsRepository(repository.db).read()).reminders.toList(),
    applyReminders: (_) => ReminderSync(repository).apply(),
    preferencesChanged: () => ref.invalidate(appSettingsProvider),
  );
});
