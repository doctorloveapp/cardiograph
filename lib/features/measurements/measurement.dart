import '../../core/health_ranges.dart';
import 'dart:math';
import '../../core/time/measurement_time.dart';
import '../../core/validation/measurement_validation.dart';

String newMeasurementId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class Measurement {
  final String id, zone, localDate, localTime, source, note;
  final int systolic, diastolic, pulse, offsetMinutes, revision;
  final DateTime measuredAtUtc, createdAtUtc, updatedAtUtc;
  final DateTime? originalCapturedAtUtc;
  const Measurement({
    required this.id,
    required this.systolic,
    required this.diastolic,
    required this.pulse,
    required this.measuredAtUtc,
    required this.zone,
    required this.offsetMinutes,
    required this.localDate,
    required this.localTime,
    this.source = 'manual',
    this.note = '',
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.revision = 0,
    this.originalCapturedAtUtc,
  });
  DateTime get wall => DateTime.parse('${localDate}T${localTime}Z');
  DayBand get band => bandFor(wall);
  String get periodAnchorDate => anchorDate(wall);
  bool get nocturnal => wall.hour < 7;
  PressureRange get pressureCategory => pressureRange(systolic, diastolic);
  PulseRange get pulseCategory => pulseRange(pulse);
  bool get elevated =>
      systolicHigh(systolic) || diastolicHigh(diastolic) || pulseHigh(pulse);
  void validate() {
    if ([systolic, diastolic, pulse].any((v) => numberError('$v') != null) ||
        note.runes.length > 500 ||
        !['manual', 'camera'].contains(source)) {
      throw ArgumentError('Misurazione non valida');
    }
    final reconstructed = measuredAtUtc.toUtc().add(
      Duration(minutes: offsetMinutes),
    );
    if (dateKey(reconstructed) != localDate ||
        timeKey(reconstructed) != localTime) {
      throw ArgumentError('Data incoerente');
    }
  }

  Map<String, Object?> get values => {
    'id': id,
    'systolic': systolic,
    'diastolic': diastolic,
    'pulse': pulse,
    'measured_at_utc': measuredAtUtc.millisecondsSinceEpoch,
    'zone': zone,
    'offset_minutes': offsetMinutes,
    'local_date': localDate,
    'local_time': localTime,
    'source': source,
    'created_at_utc': createdAtUtc.millisecondsSinceEpoch,
    'updated_at_utc': updatedAtUtc.millisecondsSinceEpoch,
    'revision': revision,
    'original_captured_at_utc': originalCapturedAtUtc?.millisecondsSinceEpoch,
    'note': note,
  };
  factory Measurement.fromRow(Map<String, dynamic> d) => Measurement(
    id: d['id'] as String,
    systolic: d['systolic'] as int,
    diastolic: d['diastolic'] as int,
    pulse: d['pulse'] as int,
    measuredAtUtc: DateTime.fromMillisecondsSinceEpoch(
      d['measured_at_utc'] as int,
      isUtc: true,
    ),
    zone: d['zone'] as String,
    offsetMinutes: d['offset_minutes'] as int,
    localDate: d['local_date'] as String,
    localTime: d['local_time'] as String,
    source: d['source'] as String,
    note: d['note'] as String,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      d['created_at_utc'] as int,
      isUtc: true,
    ),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      d['updated_at_utc'] as int,
      isUtc: true,
    ),
    revision: d['revision'] as int,
    originalCapturedAtUtc: d['original_captured_at_utc'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            d['original_captured_at_utc'] as int,
            isUtc: true,
          ),
  );
}

class MetricStats {
  final int count;
  final double? mean;
  final int? minimum, maximum;
  MetricStats(Iterable<int> values) : this._(values.toList());
  MetricStats._(List<int> values)
    : count = values.length,
      mean = values.isEmpty
          ? null
          : values.reduce((a, b) => a + b) / values.length,
      minimum = values.isEmpty ? null : values.reduce(min),
      maximum = values.isEmpty ? null : values.reduce(max);
}

class MeasurementStats {
  final int count, days;
  final MetricStats systolic, diastolic, pulse;
  MeasurementStats(List<Measurement> rows)
    : count = rows.length,
      days = rows.map((m) => m.localDate).toSet().length,
      systolic = MetricStats(rows.map((m) => m.systolic)),
      diastolic = MetricStats(rows.map((m) => m.diastolic)),
      pulse = MetricStats(rows.map((m) => m.pulse));
}
