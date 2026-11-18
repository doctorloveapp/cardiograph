import 'dart:math' as math;
import '../../core/time/measurement_time.dart';
import '../measurements/measurement.dart';

enum ReportMode { day, week, month, custom, all }

class ReportPeriod {
  final CivilPeriod civil;
  ReportPeriod._(DateTime a, DateTime b)
    : civil = CivilPeriod(dateKey(a), dateKey(b));
  factory ReportPeriod.day(DateTime d) => ReportPeriod._(d, d);
  factory ReportPeriod.week(DateTime d) {
    final monday = DateTime.utc(d.year, d.month, d.day - d.weekday + 1);
    return ReportPeriod._(
      monday,
      DateTime.utc(monday.year, monday.month, monday.day + 6),
    );
  }
  factory ReportPeriod.month(int year, int month) => ReportPeriod._(
    DateTime.utc(year, month),
    DateTime.utc(year, month + 1, 0),
  );
  factory ReportPeriod.custom(DateTime a, DateTime b) => ReportPeriod._(a, b);
  factory ReportPeriod.covering(Iterable<Measurement> rows) {
    final dates = rows.map((m) => m.localDate).toList()..sort();
    if (dates.isEmpty) throw StateError('Nessuna misurazione nel periodo');
    return ReportPeriod._(
      DateTime.parse(dates.first),
      DateTime.parse(dates.last),
    );
  }
  String get label => '${displayDate(civil.start)} – ${displayDate(civil.end)}';
}

String displayDate(String iso) => iso.split('-').reversed.join('/');
String bandLabel(DayBand band) => ['Mattina', 'Pomeriggio', 'Sera'][band.index];

class ReportSnapshot {
  final ReportPeriod period;
  final List<Measurement> rows;
  final DateTime generatedAt;
  final String heading;
  ReportSnapshot({
    required this.period,
    required Iterable<Measurement> rows,
    required this.generatedAt,
    this.heading = '',
  }) : rows = List.unmodifiable(
         rows.where((m) => period.civil.contains(m.localDate)).toList()
           ..sort((a, b) {
             final c = '${a.localDate} ${a.localTime}'.compareTo(
               '${b.localDate} ${b.localTime}',
             );
             return c == 0 ? a.measuredAtUtc.compareTo(b.measuredAtUtc) : c;
           }),
       ) {
    if (heading.length > 160 || heading.toLowerCase().contains('dan king')) {
      throw ArgumentError('Intestazione non valida');
    }
    if (this.rows.length > 10000) {
      throw ArgumentError('Seleziona un periodo con meno di 10.001 letture');
    }
  }
  MeasurementStats get stats => MeasurementStats(rows);
  bool get showOffsets =>
      rows.map((m) => (m.zone, m.offsetMinutes)).toSet().length > 1;
}

/// Regular numeric Y-axis ticks, bounded in count and independent for each chart.
class ReportChartScale {
  final double minimum, maximum, step;
  const ReportChartScale(this.minimum, this.maximum, this.step);
  factory ReportChartScale.fromValues(Iterable<num> original) {
    final values = original.map((v) => v.toDouble()).toList();
    if (values.isEmpty) throw ArgumentError('Scala senza valori');
    final lower = math.max(0, values.reduce(math.min) - 10).toDouble();
    final upper = (values.reduce(math.max) + 20).toDouble();
    final raw = (upper - lower) / 7;
    final power = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final fraction = raw / power;
    final step =
        (fraction <= 1
            ? 1
            : fraction <= 2
            ? 2
            : fraction <= 5
            ? 5
            : 10) *
        power;
    return ReportChartScale(
      (lower / step).floor() * step,
      (upper / step).ceil() * step,
      step,
    );
  }
  List<double> get ticks => [
    for (var i = 0; i <= ((maximum - minimum) / step).round(); i++)
      minimum + i * step,
  ];
}
