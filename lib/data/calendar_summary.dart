class CalendarDaySummary {
  final String date;
  final int count, morning, afternoon, evening, highCount;
  const CalendarDaySummary(
    this.date,
    this.count,
    this.morning,
    this.afternoon,
    this.evening,
    this.highCount,
  );
  bool get elevated => highCount > 0;
}
