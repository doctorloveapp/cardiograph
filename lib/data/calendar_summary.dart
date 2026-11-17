import '../core/health_ranges.dart';

class CalendarDaySummary {
  final String date;
  final int count, morning, afternoon, evening, highCount;
  const CalendarDaySummary(
    this.date,
    this.count,
    this.morning,
    this.afternoon,
    this.evening,
    this.highCount, [
    this.category = PressureRange.normal,
  ]);
  final PressureRange category;
  bool get elevated => highCount > 0;
}
