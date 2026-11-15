import '../../app/version.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../../data/repositories.dart';
import '../measurements/measurement.dart';

const maxBackupBytes = 64 * 1024 * 1024, maxBackupReadings = 100000;
bool _zonesReady = false;

class BackupFailure implements Exception {
  final String message;
  const BackupFailure(this.message);
  @override
  String toString() => message;
}

Never _invalid([String message = 'Backup non valido o non supportato']) =>
    throw BackupFailure(message);

/// Sorted object keys, UTF-8, integer numbers only, no whitespace. Format v1.
String canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonical).join(',')}]';
  if (value == null || value is String || value is bool || value is int) {
    return jsonEncode(value);
  }
  return _invalid();
}

Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(canonical(value)));
Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : _invalid();
void _keys(Map<String, dynamic> m, Set<String> keys) {
  if (m.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(m.keys.toSet()).isNotEmpty) {
    _invalid();
  }
}

String _str(Object? v, int max) =>
    v is String && v.length <= max && !v.contains('\u0000') ? v : _invalid();
int _int(Object? v, int min, int max) =>
    v is int && v >= min && v <= max ? v : _invalid();
bool _bool(Object? v) => v is bool ? v : _invalid();
List<int> _b64(Object? value, int min, int max) {
  final str = _str(value, ((max + 2) ~/ 3) * 4);
  try {
    final b = base64Decode(str);
    if (b.length < min || b.length > max || base64Encode(b) != str) _invalid();
    return b;
  } on FormatException {
    return _invalid();
  }
}

bool equalBytes(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

Future<String> payloadDigest(String text) async =>
    base64Encode((await Sha256().hash(utf8.encode(text))).bytes);

/// Reject duplicate keys and deep structures before Dart's recursive JSON parser.
Object? _parse(Uint8List bytes) {
  if (bytes.length > maxBackupBytes) {
    _invalid('Il file supera il limite di 64 MiB');
  }
  try {
    final text = utf8.decode(bytes);
    final stack = <Set<String>?>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 34) {
        final start = i;
        i++;
        while (i < text.length) {
          if (text.codeUnitAt(i) == 92) {
            i += 2;
            continue;
          }
          if (text.codeUnitAt(i) == 34) break;
          i++;
        }
        if (i >= text.length) _invalid('File troncato');
        var after = i + 1;
        while (after < text.length && text.codeUnitAt(after) <= 32) {
          after++;
        }
        if (after < text.length && text.codeUnitAt(after) == 58) {
          if (stack.isEmpty || stack.last == null || i - start > 128) {
            _invalid();
          }
          final key = jsonDecode(text.substring(start, i + 1)) as String;
          if (!stack.last!.add(key)) _invalid('Chiavi duplicate nel backup');
        }
      } else if (c == 123 || c == 91) {
        stack.add(c == 123 ? <String>{} : null);
        if (stack.length > 16) {
          _invalid('Struttura del backup troppo complessa');
        }
      } else if (c == 125 || c == 93) {
        if (stack.isEmpty) _invalid();
        stack.removeLast();
      }
    }
    return jsonDecode(text);
  } on FormatException {
    return _invalid('File troncato o JSON non valido');
  }
}

class BackupArchive {
  final List<Measurement> rows;
  final AppSettings settings;
  BackupArchive(Iterable<Measurement> rows, this.settings)
    : rows = List.unmodifiable(rows);
  String? get firstDate => rows.isEmpty
      ? null
      : (rows.map((m) => m.localDate).toList()..sort()).first;
  String? get lastDate => rows.isEmpty
      ? null
      : (rows.map((m) => m.localDate).toList()..sort()).last;
  Map<String, dynamic> get payload => {
    'schemaVersion': 2,
    'readings': (rows.toList()..sort((a, b) => a.id.compareTo(b.id)))
        .map(
          (m) => {
            'id': m.id,
            'systolic': m.systolic,
            'diastolic': m.diastolic,
            'pulse': m.pulse,
            'measuredAtUtc': m.measuredAtUtc.toUtc().toIso8601String(),
            'zone': m.zone,
            'offsetMinutes': m.offsetMinutes,
            'localDate': m.localDate,
            'localTime': m.localTime,
            'source': m.source,
            'note': m.note,
            'createdAtUtc': m.createdAtUtc.toUtc().toIso8601String(),
            'updatedAtUtc': m.updatedAtUtc.toUtc().toIso8601String(),
            'revision': m.revision,
            'originalCapturedAtUtc': m.originalCapturedAtUtc
                ?.toUtc()
                .toIso8601String(),
          },
        )
        .toList(),
    'preferences': settings.portable,
  };
  factory BackupArchive.validate(Object? value) {
    if (!_zonesReady) {
      tzdata.initializeTimeZones();
      _zonesReady = true;
    }
    final p = Map<String, dynamic>.from(_map(value));
    _keys(p, {'schemaVersion', 'readings', 'preferences'});
    final version = _int(p['schemaVersion'], 1, 2);
    final records = p['readings'];
    if (records is! List || records.length > maxBackupReadings) {
      _invalid('Limite di 100.000 letture superato');
    }
    final ids = <String>{};
    final rows = <Measurement>[];
    for (final record in records) {
      final r = Map<String, dynamic>.from(_map(record));
      if (version == 1) {
        r.putIfAbsent('note', () => '');
        r.putIfAbsent('originalCapturedAtUtc', () => null);
      }
      _keys(r, {
        'id',
        'systolic',
        'diastolic',
        'pulse',
        'measuredAtUtc',
        'zone',
        'offsetMinutes',
        'localDate',
        'localTime',
        'source',
        'note',
        'createdAtUtc',
        'updatedAtUtc',
        'revision',
        'originalCapturedAtUtc',
      });
      final id = _str(r['id'], 128);
      if (id.trim().isEmpty ||
          !ids.add(id) ||
          id.codeUnits.any((c) => c < 32)) {
        _invalid('ID duplicato o non valido');
      }
      DateTime utc(Object? v) {
        final text = _str(v, 32);
        if (!RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3}(\d{3})?)?Z$',
        ).hasMatch(text)) {
          _invalid('Timestamp UTC non valido');
        }
        final d = DateTime.tryParse(text);
        if (d == null ||
            d.year < 1900 ||
            d.year > 2200 ||
            !text.startsWith(d.toIso8601String().substring(0, 19))) {
          _invalid('Timestamp non valido');
        }
        return d;
      }

      final zone = _str(r['zone'], 100);
      try {
        tz.getLocation(zone);
      } catch (_) {
        _invalid('Fuso orario non supportato');
      }
      final date = _str(r['localDate'], 10), time = _str(r['localTime'], 8);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          !RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(time)) {
        _invalid('Data/ora locale non valida');
      }
      final source = _str(r['source'], 8), note = _str(r['note'], 1000);
      if (!['manual', 'camera'].contains(source) ||
          note.runes.length > 500 ||
          note.codeUnits.any((c) => c < 32 && ![9, 10, 13].contains(c))) {
        _invalid('Origine o nota non valida');
      }
      final m = Measurement(
        id: id,
        systolic: _int(r['systolic'], 1, 999),
        diastolic: _int(r['diastolic'], 1, 999),
        pulse: _int(r['pulse'], 1, 999),
        measuredAtUtc: utc(r['measuredAtUtc']),
        zone: zone,
        offsetMinutes: _int(r['offsetMinutes'], -840, 840),
        localDate: date,
        localTime: time,
        source: source,
        note: note,
        createdAtUtc: utc(r['createdAtUtc']),
        updatedAtUtc: utc(r['updatedAtUtc']),
        revision: _int(r['revision'], 0, 2147483647),
        originalCapturedAtUtc: r['originalCapturedAtUtc'] == null
            ? null
            : utc(r['originalCapturedAtUtc']),
      );
      if (m.updatedAtUtc.isBefore(m.createdAtUtc) ||
          (m.originalCapturedAtUtc != null && source != 'camera')) {
        _invalid('Metadati temporali incoerenti');
      }
      try {
        m.validate();
      } catch (_) {
        _invalid('Date e offset incoerenti');
      }
      rows.add(m);
    }
    final prefs = Map<String, dynamic>.from(_map(p['preferences']));
    if (version == 1) prefs.putIfAbsent('opaque', () => false);
    _keys(prefs, {'protectBackupWithPassword', 'opaque', 'reminders'});
    final reminders = prefs['reminders'];
    if (reminders is! List || reminders.length != 3) {
      _invalid('Preferenze non valide');
    }
    return BackupArchive(
      rows,
      AppSettings(
        protectBackupWithPassword: _bool(prefs['protectBackupWithPassword']),
        opaque: _bool(prefs['opaque']),
        reminders: reminders.map(_bool).toList(),
      ),
    );
  }
}

class BackupEnvelope {
  final Map<String, dynamic> data, header;
  BackupEnvelope._(this.data, this.header);
  bool get encrypted => header['protection'] == 'aes256gcm';
  factory BackupEnvelope.inspect(Uint8List bytes) {
    final e = _map(_parse(bytes)), h = _map(e['header']);
    final protection = h['protection'];
    if (h['magic'] != 'CardioGraphBackup' ||
        h['formatVersion'] is! int ||
        h['formatVersion'] != 1 ||
        !['none', 'aes256gcm'].contains(protection)) {
      _invalid('Formato o versione non supportati');
    }
    final appVersion = _str(h['appVersion'], 32),
        created = _str(h['createdAtUtc'], 32);
    if (!RegExp(
          r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$',
        ).hasMatch(appVersion) ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?Z$',
        ).hasMatch(created) ||
        DateTime.tryParse(created) == null ||
        !created.startsWith(
          DateTime.parse(created).toIso8601String().substring(0, 19),
        )) {
      _invalid('Intestazione non valida');
    }
    if (protection == 'none') {
      _keys(h, {
        'magic',
        'formatVersion',
        'appVersion',
        'createdAtUtc',
        'protection',
      });
      _keys(e, {'header', 'payload', 'checksum'});
      _b64(e['checksum'], 32, 32);
    } else {
      _keys(h, {
        'magic',
        'formatVersion',
        'appVersion',
        'createdAtUtc',
        'protection',
        'nonce',
        'kdf',
      });
      _keys(e, {'header', 'ciphertext', 'tag'});
      _b64(h['nonce'], 12, 12);
      _b64(e['tag'], 16, 16);
      final k = _map(h['kdf']);
      _keys(k, {
        'algorithm',
        'version',
        'memoryKiB',
        'iterations',
        'parallelism',
        'salt',
      });
      for (final (key, value) in [
        ('version', 19),
        ('memoryKiB', 65536),
        ('iterations', 3),
        ('parallelism', 1),
      ]) {
        _int(k[key], value, value);
      }
      if (k['algorithm'] != 'argon2id' ||
          k['version'] != 19 ||
          k['memoryKiB'] != 65536 ||
          k['iterations'] != 3 ||
          k['parallelism'] != 1) {
        _invalid('Parametri KDF non consentiti');
      }
      _b64(k['salt'], 16, 32);
      _str(e['ciphertext'], maxBackupBytes);
    }
    return BackupEnvelope._(e, h);
  }
  Future<BackupArchive> decode({String? passphrase}) async {
    Object? payload;
    if (!encrypted) {
      final hash = await Sha256().hash(
        _bytes({'header': header, 'payload': data['payload']}),
      );
      if (!equalBytes(hash.bytes, _b64(data['checksum'], 32, 32))) {
        _invalid('Checksum non valido: backup alterato o corrotto');
      }
      payload = data['payload'];
    } else {
      if (passphrase == null || utf8.encode(passphrase).length > 1024) {
        _invalid('Password richiesta o troppo lunga');
      }
      final key = await _derive(
        passphrase,
        _b64(_map(header['kdf'])['salt'], 16, 32),
      );
      try {
        final clear = await AesGcm.with256bits().decrypt(
          SecretBox(
            _b64(data['ciphertext'], 1, maxBackupBytes),
            nonce: _b64(header['nonce'], 12, 12),
            mac: Mac(_b64(data['tag'], 16, 16)),
          ),
          secretKey: key,
          aad: _bytes(header),
        );
        try {
          payload = _parse(Uint8List.fromList(clear));
        } finally {
          if (clear is Uint8List) clear.fillRange(0, clear.length, 0);
        }
      } on SecretBoxAuthenticationError {
        _invalid('Password errata o backup alterato');
      } finally {
        key.destroy();
      }
    }
    return BackupArchive.validate(payload);
  }
}

Future<SecretKey> _derive(String password, List<int> salt) async {
  final bytes = Uint8List.fromList(utf8.encode(password));
  final secret = SecretKey(bytes);
  try {
    return await Argon2id(
      memory: 65536,
      iterations: 3,
      parallelism: 1,
      hashLength: 32,
    ).deriveKey(secretKey: secret, nonce: salt);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
    secret.destroy();
  }
}

Future<Uint8List> encodeBackup(
  BackupArchive archive, {
  String? passphrase,
  required DateTime now,
}) async {
  final valid = BackupArchive.validate(archive.payload);
  final h = <String, dynamic>{
    'magic': 'CardioGraphBackup',
    'formatVersion': 1,
    'appVersion': AppVersion.name,
    'createdAtUtc': now.toUtc().toIso8601String(),
    'protection': passphrase == null ? 'none' : 'aes256gcm',
  };
  final payload = valid.payload;
  Map<String, dynamic> result;
  if (passphrase == null) {
    result = {
      'header': h,
      'payload': payload,
      'checksum': base64Encode(
        (await Sha256().hash(_bytes({'header': h, 'payload': payload}))).bytes,
      ),
    };
  } else {
    if (passphrase.runes.length < 8 || utf8.encode(passphrase).length > 1024) {
      _invalid('Usa una password di almeno 8 caratteri e massimo 1024 byte');
    }
    final algorithm = AesGcm.with256bits();
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    h['nonce'] = base64Encode(algorithm.newNonce());
    h['kdf'] = {
      'algorithm': 'argon2id',
      'version': 19,
      'memoryKiB': 65536,
      'iterations': 3,
      'parallelism': 1,
      'salt': base64Encode(salt),
    };
    final key = await _derive(passphrase, salt);
    final clear = _bytes(payload);
    try {
      final box = await algorithm.encrypt(
        clear,
        secretKey: key,
        nonce: base64Decode(h['nonce'] as String),
        aad: _bytes(h),
      );
      result = {
        'header': h,
        'ciphertext': base64Encode(box.cipherText),
        'tag': base64Encode(box.mac.bytes),
      };
    } finally {
      clear.fillRange(0, clear.length, 0);
      key.destroy();
    }
  }
  final bytes = _bytes(result);
  if (bytes.length > maxBackupBytes) {
    _invalid('Il backup supera 64 MiB: nessuna esportazione parziale');
  }
  return bytes;
}
