import 'package:timezone/timezone.dart' as tz;

enum DayBand { morning, afternoon, evening }

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String timeKey(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
DayBand bandFor(DateTime wall) {
  final minute = wall.hour * 60 + wall.minute;
  if (minute >= 420 && minute <= 780) return DayBand.morning;
  if (minute >= 781 && minute <= 1140) return DayBand.afternoon;
  return DayBand.evening;
}

String anchorDate(DateTime wall) => dateKey(
  wall.hour < 7 ? DateTime.utc(wall.year, wall.month, wall.day - 1) : wall,
);

/// UTC-constructed wall components are deliberately distinct from an instant.
/// Enumerating candidate offsets avoids silently normalizing DST gaps or folds.
List<tz.TZDateTime> resolveWall(DateTime wall, String zone) {
  final location = tz.getLocation(zone);
  final nominal = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
  final offsets = <int>{};
  for (var h = -36; h <= 36; h++) {
    offsets.add(
      tz.TZDateTime.from(
        nominal.add(Duration(hours: h)),
        location,
      ).timeZoneOffset.inMilliseconds,
    );
  }
  final candidates = <tz.TZDateTime>[];
  for (final offset in offsets) {
    final candidate = tz.TZDateTime.from(
      nominal.subtract(Duration(milliseconds: offset)),
      location,
    );
    if (dateKey(candidate) == dateKey(nominal) &&
        timeKey(candidate) == timeKey(nominal)) {
      candidates.add(candidate);
    }
  }
  candidates.sort((a, b) => a.compareTo(b));
  return candidates;
}

class CivilPeriod {
  final String start, end;
  CivilPeriod(this.start, this.end) {
    if (start.compareTo(end) > 0) throw ArgumentError('Intervallo non valido');
  }
  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
}
