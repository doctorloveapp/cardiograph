import '../../core/health_ranges.dart';
import '../../core/text/italian.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/time/measurement_time.dart';
import '../analytics/analytics_model.dart';
import '../measurements/measurement.dart';
import 'report_model.dart';

const _ink = PdfColor.fromInt(0xff16334b);
const _blue = PdfColor.fromInt(0xff1261c9);
const _green = PdfColor.fromInt(0xff006b5e);

String _number(num v) =>
    v is int ? '$v' : v.toStringAsFixed(1).replaceAll('.', ',');

/// CPU-only, suitable for compute(). No network fonts or raster chart screenshots.
Future<Uint8List> buildReportPdf(
  (ReportSnapshot, Uint8List, Uint8List) request,
) async {
  final (s, logo, fontBytes) = request;
  if (s.rows.isEmpty) throw StateError('Nessuna misurazione nel periodo');
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final doc = pw.Document(
    title: 'CardioGraph · Diario pressorio',
    author: '',
    creator: 'CardioGraph',
    subject: 'Diario personale delle misurazioni',
  );
  final regular = pw.TextStyle(font: font, fontSize: 9, color: _ink);
  pw.Widget text(String value, {double size = 9}) =>
      pw.Text(value, style: regular.copyWith(fontSize: size));
  pw.Widget number(num value, Metric metric, {int? hex}) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        width: 5,
        height: 5,
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(hex ?? metric.rangeHex(value)),
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: _ink, width: .3),
        ),
      ),
      pw.SizedBox(width: 3),
      pw.Text(_number(value), style: regular),
    ],
  );
  final distribution = PressureDistribution(
    s.rows.map((m) => m.pressureCategory),
  );
  pw.Widget summary(String title, List<Measurement> rows) {
    final stats = MeasurementStats(rows);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text(
            '$title · ${stats.count} ${stats.count == 1 ? 'lettura' : 'letture'} · ${stats.days} ${stats.days == 1 ? 'giorno' : 'giorni'}',
            size: 11,
          ),
          if (rows.isEmpty) text('Nessuna misurazione'),
          if (rows.isNotEmpty)
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(),
                2: const pw.FlexColumnWidth(),
                3: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    'Parametro',
                    'Media',
                    'Minimo',
                    'Massimo',
                  ].map(text).toList(),
                ),
                for (final metric in Metric.values)
                  (() {
                    final st = MetricStats(rows.map(metric.value));
                    return pw.TableRow(
                      children: [
                        text('${metric.label} (${metric.unit})'),
                        number(st.mean!, metric),
                        number(st.minimum!, metric),
                        number(st.maximum!, metric),
                      ],
                    );
                  })(),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget cell(pw.Widget child) =>
      pw.Padding(padding: const pw.EdgeInsets.all(5), child: child);
  String offset(int n) =>
      'UTC${n < 0 ? '-' : '+'}${(n.abs() ~/ 60).toString().padLeft(2, '0')}:${(n.abs() % 60).toString().padLeft(2, '0')}';
  // Break only unusually long unspaced tokens; ordinary Italian wraps naturally.
  // Print whitespace uniformly: a pasted note with hundreds of newlines must
  // never create a table row taller than an A4 page. All words remain intact.
  String note(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAllMapped(RegExp(r'\S{24,}'), (m) {
        final runes = m[0]!.runes.toList();
        return [
          for (var i = 0; i < runes.length; i += 24)
            String.fromCharCodes(
              runes.sublist(i, math.min(i + 24, runes.length)),
            ),
        ].join('\n');
      });
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 10001,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (c) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Image(
              pw.MemoryImage(logo),
              width: 48,
              height: 48,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text('CardioGraph · Diario pressorio', size: 18),
                  if (s.heading.trim().isNotEmpty)
                    text(s.heading.trim(), size: 11),
                  text('Periodo: ${s.period.label}'),
                  text(
                    'Generato il ${displayDate(dateKey(s.generatedAt))} alle ${timeKey(s.generatedAt)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: (c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('CardioGraph · Diario personale', size: 8),
            text('Pagina ${c.pageNumber} di ${c.pagesCount}', size: 8),
          ],
        ),
      ),
      build: (c) => [
        pw.SizedBox(height: 12),
        text(
          'Diario personale: i valori sono stati inseriti o confermati dall’utente',
        ),
        pw.SizedBox(height: 6),
        pw.SizedBox(height: 14),
        summary('Riepilogo generale', s.rows),
        for (final band in DayBand.values)
          summary(
            bandLabel(band),
            s.rows.where((m) => m.band == band).toList(),
          ),
        pw.SizedBox(height: 8),
        _chart(s, [Metric.systolic, Metric.diastolic], text),
        pw.SizedBox(height: 12),
        _chart(s, [Metric.pulse], text),
        pw.NewPage(),
        text('Distribuzione pressione', size: 15),
        pw.SizedBox(height: 12),
        pw.SizedBox(
          height: 200,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (final r in PressureRange.values)
                if (distribution.counts[r]! > 0)
                  pw.PieDataSet(
                    value: distribution.counts[r]!,
                    color: PdfColor.fromInt(r.hex),
                    innerRadius: 30,
                    legendPosition: pw.PieLegendPosition.inside,
                    legendWidget: pw.Text(
                      '${distribution.percent(r).toStringAsFixed(1)}%',
                      style: regular.copyWith(
                        color: PdfColors.black,
                        fontSize: distribution.percent(r) < 5 ? 7 : 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        for (final r in PressureRange.values)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(r.hex),
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: _ink, width: .4),
                  ),
                ),
                pw.SizedBox(width: 8),
                text(r.compactLabel),
              ],
            ),
          ),
        pw.SizedBox(height: 12),
        pw.NewPage(),
        text(
          'Elenco completo · ${countNoun(s.rows.length, 'lettura', 'letture')}',
          size: 13,
        ),
        if (s.showOffsets)
          text(
            'Orari locali registrati; offset UTC riportato per distinguere i fusi.',
          ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey300,
              width: .4,
            ),
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(57),
            1: const pw.FixedColumnWidth(57),
            2: const pw.FixedColumnWidth(65),
            3: const pw.FixedColumnWidth(43),
            4: const pw.FixedColumnWidth(43),
            5: const pw.FixedColumnWidth(45),
            6: const pw.FlexColumnWidth(),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                'Data',
                'Ora',
                'Fascia',
                'Max\nmmHg',
                'Min\nmmHg',
                'Battiti\nbpm',
                'Nota',
              ].map((t) => cell(text(t, size: 8))).toList(),
            ),
            for (final m in s.rows)
              pw.TableRow(
                children: [
                  cell(text(displayDate(m.localDate), size: 8)),
                  cell(
                    text(
                      '${m.localTime}${s.showOffsets ? '\n${offset(m.offsetMinutes)}' : ''}',
                      size: 8,
                    ),
                  ),
                  cell(
                    text(
                      '${bandLabel(m.band)}${m.nocturnal ? '\nNotturna' : ''}',
                      size: 8,
                    ),
                  ),
                  cell(
                    number(
                      m.systolic,
                      Metric.systolic,
                      hex: m.pressureCategory.hex,
                    ),
                  ),
                  cell(
                    number(
                      m.diastolic,
                      Metric.diastolic,
                      hex: m.pressureCategory.hex,
                    ),
                  ),
                  cell(number(m.pulse, Metric.pulse)),
                  cell(text(note(m.note), size: 8)),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _chart(
  ReportSnapshot s,
  List<Metric> metrics,
  pw.Widget Function(String, {double size}) text,
) {
  final values = [
    for (final m in s.rows)
      for (final k in metrics) k.value(m),
    ...metrics.expand((k) => k.guides).map((v) => v.toInt()),
  ];
  final minY = (values.reduce(math.min) ~/ 10) * 10 - 10;
  final maxY = (values.reduce(math.max) ~/ 10 + 2) * 10;
  final first = s.rows.first.wall.millisecondsSinceEpoch;
  final last = s.rows.last.wall.millisecondsSinceEpoch;
  const width = 488.0, height = 100.0;
  double x(Measurement m) => last == first
      ? width / 2
      : (m.wall.millisecondsSinceEpoch - first) / (last - first) * width;
  double y(num n) => (n - minY) / (maxY - minY) * height;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      text(
        metrics.length == 2
            ? 'Pressione (mmHg) · Massima: cerchi · Minima: quadrati'
            : 'Pulsazioni (bpm) · Colori delle categorie',
        size: 10,
      ),
      text(
        'Scala: $minY–$maxY · Riferimenti: ${metrics.expand((k) => k.guides).toSet().join(' / ')}',
        size: 8,
      ),
      pw.SizedBox(height: 5),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        child: pw.CustomPaint(
          size: const PdfPoint(width + 8, height + 8),
          painter: (g, size) {
            g.saveContext();
            // All coordinates remain vector paths. Exact observations, straight segments, no invented dates.
            for (final metric in metrics) {
              final color = metric == Metric.diastolic ? _green : _blue;
              for (final reference in metric.guides) {
                g
                  ..setStrokeColor(PdfColors.grey500)
                  ..setLineWidth(.5)
                  ..setLineDashPattern([3, 3])
                  ..drawLine(4, y(reference) + 4, width + 4, y(reference) + 4)
                  ..strokePath()
                  ..setLineDashPattern();
              }
              g
                ..setStrokeColor(color)
                ..setLineWidth(.8);
              for (var i = 1; i < s.rows.length; i++) {
                g.drawLine(
                  x(s.rows[i - 1]) + 4,
                  y(metric.value(s.rows[i - 1])) + 4,
                  x(s.rows[i]) + 4,
                  y(metric.value(s.rows[i])) + 4,
                );
              }
              g.strokePath();
              for (final m in s.rows) {
                g.setFillColor(
                  PdfColor.fromInt(metric.rangeHex(metric.value(m))),
                );
                if (metric == Metric.diastolic) {
                  g.drawRect(x(m) + 2, y(metric.value(m)) + 2, 4, 4);
                } else {
                  g.drawEllipse(x(m) + 4, y(metric.value(m)) + 4, 2, 2);
                }
                g.fillPath();
              }
            }
            g.restoreContext();
          },
        ),
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text(
            '${displayDate(s.rows.first.localDate)} ${s.rows.first.localTime}',
            size: 8,
          ),
          text(
            '${displayDate(s.rows.last.localDate)} ${s.rows.last.localTime}',
            size: 8,
          ),
        ],
      ),
      text(
        'Ogni punto è una lettura originale; nessun valore inserito nei giorni senza dati.',
        size: 8,
      ),
    ],
  );
}
