import '../../core/text/italian.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/services/platform_services.dart';
import '../../data/providers.dart';
import 'report_model.dart';
import 'report_pdf.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  ReportMode _mode = ReportMode.month;
  late DateTime _day = ref.read(clockProvider).now();
  DateTimeRange? _range;
  final _heading = TextEditingController();
  bool _busy = false;
  String? _error;
  ReportPeriod get _period => switch (_mode) {
    ReportMode.all => throw StateError(
      'Periodo definito dallo snapshot completo',
    ),
    ReportMode.day => ReportPeriod.day(_day),
    ReportMode.week => ReportPeriod.week(_day),
    ReportMode.month => ReportPeriod.month(_day.year, _day.month),
    ReportMode.custom => ReportPeriod.custom(
      _range?.start ?? _day,
      _range?.end ?? _day,
    ),
  };
  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _select() async {
    if (_mode == ReportMode.custom) {
      final value = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
        initialDateRange: _range,
      );
      if (value != null && mounted) setState(() => _range = value);
    } else if (_mode == ReportMode.month) {
      var month = _day.month, year = _day.year;
      final result = await showDialog<DateTime>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => GlassDialog(
            title: const Text('Mese del report'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Mese'),
                  items: [
                    for (var n = 1; n <= 12; n++)
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          const [
                            'Gennaio',
                            'Febbraio',
                            'Marzo',
                            'Aprile',
                            'Maggio',
                            'Giugno',
                            'Luglio',
                            'Agosto',
                            'Settembre',
                            'Ottobre',
                            'Novembre',
                            'Dicembre',
                          ][n - 1],
                        ),
                      ),
                  ],
                  onChanged: (n) => update(() => month = n!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: year,
                  decoration: const InputDecoration(labelText: 'Anno'),
                  items: [
                    for (var n = 1900; n <= 2200; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (n) => update(() => year = n!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, DateTime(year, month)),
                child: const Text('Conferma'),
              ),
            ],
          ),
        ),
      );
      if (result != null && mounted) setState(() => _day = result);
    } else {
      final d = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
      );
      if (d != null && mounted) setState(() => _day = d);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(measurementRepositoryProvider.future);
      final rows = _mode == ReportMode.all
          ? await repo.snapshotAll()
          : await repo.snapshot(_period.civil);
      if (rows.isEmpty) throw StateError('Nessuna misurazione nel periodo');
      final snapshot = ReportSnapshot(
        period: _mode == ReportMode.all ? ReportPeriod.covering(rows) : _period,
        rows: rows,
        heading: _heading.text.trim(),
        generatedAt: ref.read(clockProvider).now(),
      );
      if (snapshot.rows.isEmpty) {
        throw StateError('Nessuna misurazione nel periodo');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => GlassDialog(
          title: const Text('Riepilogo report'),
          content: Text(
            '${snapshot.period.label}\n${countNoun(snapshot.rows.length, 'lettura', 'letture')}\nIntestazione: ${snapshot.heading.isEmpty ? 'Nessuna' : snapshot.heading}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Genera PDF'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final assets = await Future.wait([
        rootBundle.load('assets/logo.png'),
        rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      ]);
      final bytes = await compute(buildReportPdf, (
        snapshot,
        assets[0].buffer.asUint8List(),
        assets[1].buffer.asUint8List(),
      ));
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportPreviewPage(
            bytes: bytes,
            filename:
                'CardioGraph_${snapshot.period.civil.start}_${snapshot.period.civil.end}.pdf',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : e is ArgumentError
              ? '${e.message}'
              : 'Impossibile generare il report. Riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Report PDF', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ReportMode>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Periodo'),
              items: [
                for (final m in ReportMode.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(
                      const [
                        'Giorno specifico',
                        'Settimana specifica',
                        'Mese specifico',
                        'Intervallo personalizzato',
                        'Tutte le misurazioni',
                      ][m.index],
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _mode = v!),
            ),
            const SizedBox(height: 16),
            if (_mode == ReportMode.all)
              ref
                  .watch(measurementsProvider)
                  .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) =>
                        const Text('Impossibile leggere l’archivio'),
                    data: (rows) => Text(
                      rows.isEmpty
                          ? 'Nessuna misurazione nel periodo'
                          : ReportPeriod.covering(rows).label,
                    ),
                  )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : _select,
                icon: const Icon(Icons.date_range),
                label: Text(_period.label),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _heading,
              maxLength: 160,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Intestazione facoltativa',
                hintText: 'Ad esempio: diario personale',
              ),
            ),
            const Text(
              'Il report include tutte le letture del periodo, grafici e riepiloghi per fascia. Nessun account richiesto.',
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              label: _busy ? 'Preparazione…' : 'Prepara report',
              icon: Icons.picture_as_pdf,
              onPressed: _busy ? null : _generate,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, semanticsLabel: _error),
              ),
          ],
        ),
      ),
    ],
  );
}

class ReportPreviewPage extends StatefulWidget {
  final Uint8List bytes;
  final String filename;
  const ReportPreviewPage({
    super.key,
    required this.bytes,
    required this.filename,
  });
  @override
  State<ReportPreviewPage> createState() => _ReportPreviewPageState();
}

class _ReportPreviewPageState extends State<ReportPreviewPage> {
  bool _busy = false;
  Future<void> _action(bool share) async {
    setState(() => _busy = true);
    try {
      final service = AndroidDocumentFileService();
      String message;
      if (share) {
        await service.share(widget.bytes);
        message = 'Pannello di condivisione aperto';
      } else {
        final saved = await service.save(widget.filename, widget.bytes);
        message = saved ? 'PDF salvato' : 'Salvataggio annullato';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operazione non riuscita. Riprova.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Anteprima PDF')),
    body: Column(
      children: [
        Expanded(
          child: PdfPreview(
            build: (_) => widget.bytes,
            initialPageFormat: PdfPageFormat.a4,
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _action(false),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Salva PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _action(true),
                  icon: const Icon(Icons.share),
                  label: const Text('Condividi'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
