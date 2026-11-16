String fileDate(String iso) => iso.split('-').reversed.join('_');
String backupFilename(DateTime at) {
  final d = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'CardioGraph_${two(d.day)}_${two(d.month)}_${d.year}_${two(d.hour)}_${two(d.minute)}.cardiograph';
}

String reportFilename(String start, String end) =>
    'CardioGraph_${fileDate(start)}_${fileDate(end)}.pdf';
