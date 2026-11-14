import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const measurementV1 = '''CREATE TABLE measurements (
 id TEXT PRIMARY KEY NOT NULL,
 systolic INTEGER NOT NULL CHECK(systolic BETWEEN 1 AND 999),
 diastolic INTEGER NOT NULL CHECK(diastolic BETWEEN 1 AND 999),
 pulse INTEGER NOT NULL CHECK(pulse BETWEEN 1 AND 999),
 measured_at_utc INTEGER NOT NULL, zone TEXT NOT NULL, offset_minutes INTEGER NOT NULL,
 local_date TEXT NOT NULL, local_time TEXT NOT NULL,
 source TEXT NOT NULL CHECK(source IN ('manual','camera')),
 created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
 original_captured_at_utc INTEGER)''';

class ArchiveUnavailable implements Exception {
  final String reason;
  const ArchiveUnavailable(this.reason);
  @override
  String toString() =>
      'Archivio non disponibile. I dati esistenti non sono stati sostituiti.';
}

/// Drift custom-SQL schema: migrations and DAO own all writes. No generated files required.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.encrypted(File file, String key) {
    if (!RegExp(r'^[A-Za-z0-9_=-]{43,44}$').hasMatch(key)) {
      throw const ArchiveUnavailable('invalid-key');
    }
    return AppDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (raw) {
          if (raw.select('PRAGMA cipher').isEmpty) {
            throw const ArchiveUnavailable('cipher-unavailable');
          }
          raw.execute("PRAGMA key = '$key'");
          raw.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      await customStatement(measurementV1);
      await _upgradeV1();
    }),
    onUpgrade: (_, from, to) async {
      if (from != 1 || to != 2) {
        throw const ArchiveUnavailable('unsupported-schema');
      }
      await transaction(_upgradeV1);
    },
    beforeOpen: (details) async {
      if (details.versionBefore != null &&
          details.versionBefore! > schemaVersion) {
        throw const ArchiveUnavailable('newer-schema');
      }
    },
  );
  Future<void> _upgradeV1() async {
    await customStatement(
      "ALTER TABLE measurements ADD COLUMN note TEXT NOT NULL DEFAULT '' CHECK(length(note) <= 500)",
    );
    await customStatement(
      'CREATE INDEX measurements_local_date ON measurements(local_date)',
    );
    await customStatement(
      'CREATE INDEX measurements_utc ON measurements(measured_at_utc)',
    );
    await customStatement(
      'CREATE TABLE app_settings (id INTEGER PRIMARY KEY CHECK(id = 1), protect_backup_with_password INTEGER NOT NULL DEFAULT 0 CHECK(protect_backup_with_password IN (0,1)))',
    );
    await customStatement('INSERT INTO app_settings(id) VALUES (1)');
  }
}

abstract interface class ArchiveKeyVault {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureArchiveKeyVault implements ArchiveKeyVault {
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: 'cardiograph-database-key-v1');
  @override
  Future<void> write(String value) =>
      _storage.write(key: 'cardiograph-database-key-v1', value: value);
}

Future<AppDatabase> openArchive(File file, ArchiveKeyVault vault) async {
  final exists =
      await file.exists() ||
      await File('${file.path}-wal').exists() ||
      await File('${file.path}-shm').exists();
  var key = await vault.read();
  if (exists && key == null) throw const ArchiveUnavailable('missing-key');
  if (key == null) {
    final random = Random.secure();
    key = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    await vault.write(key);
  }
  final db = AppDatabase.encrypted(file, key);
  try {
    await db.customSelect('SELECT count(*) AS n FROM measurements').getSingle();
    return db;
  } catch (_) {
    await db.close();
    throw const ArchiveUnavailable('unreadable');
  }
}

Future<AppDatabase> openDeviceArchive() async {
  final directory = await getApplicationSupportDirectory();
  return openArchive(
    File('${directory.path}/cardiograph.sqlite'),
    SecureArchiveKeyVault(),
  );
}
