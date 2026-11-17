import '../../core/health_ranges.dart';
import '../../core/time/measurement_time.dart';
import '../measurements/measurement.dart';

enum Metric {
  systolic('Massima', 130, 'mmHg'),
  diastolic('Minima', 85, 'mmHg'),
  pulse('Pulsazioni', 100, 'bpm');

  final String label, unit;
  final int threshold;
  const Metric(this.label, this.threshold, this.unit);
  int value(Measurement m) => switch (this) {
    Metric.systolic => m.systolic,
    Metric.diastolic => m.diastolic,
    Metric.pulse => m.pulse,
  };
  bool high(num v) => v >= threshold;
  int rangeHex(num v) => switch (this) {
    Metric.systolic => systolicRange(v).hex,
    Metric.diastolic => diastolicRange(v).hex,
    Metric.pulse => pulseRange(v).hex,
  };
  String rangeLabel(num v) => switch (this) {
    Metric.systolic => systolicRange(v).label,
    Metric.diastolic => diastolicRange(v).label,
    Metric.pulse => pulseRange(v).label,
  };
  List<double> get guides => switch (this) {
    Metric.systolic => [90, 130, 140, 160],
    Metric.diastolic => [60, 85, 90, 100],
    Metric.pulse => [60, 100],
  };
}

class ChartObservation {
  final List<Measurement> originals;
  final bool daily;
  ChartObservation(this.originals, {this.daily = false});
  String get day => originals.first.localDate;
  double get x =>
      DateTime.parse(
        '${day}T${daily ? '12:00:00' : originals.first.localTime}Z',
      ).millisecondsSinceEpoch /
      86400000;
  MetricStats stats(Metric m) => MetricStats(originals.map(m.value));
}

class AnalyticsData {
  final List<Measurement> rows;
  final bool aggregated;
  late final MeasurementStats stats = MeasurementStats(rows);
  late final List<ChartObservation> observations = _observations();
  AnalyticsData(
    Iterable<Measurement> original, {
    required CivilPeriod period,
    DayBand? band,
  }) : rows =
           original
               .where(
                 (m) =>
                     period.contains(m.localDate) &&
                     (band == null || m.band == band),
               )
               .toList()
             ..sort((a, b) {
               final d = a.localDate.compareTo(b.localDate);
               if (d != 0) return d;
               final t = a.localTime.compareTo(b.localTime);
               return t != 0 ? t : a.id.compareTo(b.id);
             }),
       aggregated =
           DateTime.parse(
                 period.end,
               ).difference(DateTime.parse(period.start)).inDays >=
               30 ||
           original.length > 180;
  List<ChartObservation> _observations() {
    if (!aggregated) return rows.map((m) => ChartObservation([m])).toList();
    final days = <String, List<Measurement>>{};
    for (final m in rows) {
      days.putIfAbsent(m.localDate, () => []).add(m);
    }
    return days.values.map((v) => ChartObservation(v, daily: true)).toList();
  }
}
