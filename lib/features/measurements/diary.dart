import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_system/components.dart';
import '../../core/time/measurement_time.dart';
import '../../core/validation/measurement_validation.dart';
import '../../data/providers.dart';
import 'measurement.dart';

class ReadingCard extends StatelessWidget {
  final Measurement reading;
  final VoidCallback? onOpen;
  const ReadingCard(this.reading, {super.key, this.onOpen});
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${reading.localDate.split('-').reversed.join('/')} · ${reading.localTime}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${reading.source == 'camera' ? 'Foto' : 'Manuale'} · ${TimeBand.values[reading.band.index].label}${reading.nocturnal ? ' · notte, sera iniziata il ${reading.periodAnchorDate.split('-').reversed.join('/')}' : ''}',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            MeasurementValue(
              label: 'Massima',
              unit: 'mmHg',
              value: reading.systolic,
              elevated: systolicHigh(reading.systolic),
            ),
            MeasurementValue(
              label: 'Minima',
              unit: 'mmHg',
              value: reading.diastolic,
              elevated: diastolicHigh(reading.diastolic),
            ),
            MeasurementValue(
              label: 'Pulsazioni',
              unit: 'bpm',
              value: reading.pulse,
              elevated: pulseHigh(reading.pulse),
            ),
          ],
        ),
        if (reading.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(reading.note),
          ),
        if (onOpen != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpen,
              child: const Text('Apri lettura'),
            ),
          ),
      ],
    ),
  );
}

class ArchiveState extends ConsumerWidget {
  final Widget Function(List<Measurement>) builder;
  const ArchiveState({super.key, required this.builder});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(measurementsProvider)
      .when(
        loading: () => Center(
          child: Semantics(
            label: 'Caricamento diario',
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, st) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ErrorFeedback(
              message:
                  'Archivio non disponibile. I dati esistenti non sono stati sostituiti. Controlla lo spazio del telefono e riprova. Se la chiave non è più disponibile, conserva il dispositivo e il tuo eventuale backup per il recupero.',
              onRetry: () => ref.invalidate(databaseProvider),
            ),
          ],
        ),
        data: builder,
      );
}

class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});
  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  CivilPeriod? _period;
  Future<void> _filter() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (range != null && mounted) {
      setState(
        () => _period = CivilPeriod(dateKey(range.start), dateKey(range.end)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diario'),
      leading: BackButton(onPressed: () => context.pop()),
      actions: [
        IconButton(
          tooltip: 'Filtra periodo',
          onPressed: _filter,
          icon: const Icon(Icons.filter_alt_outlined),
        ),
      ],
    ),
    body: ArchiveState(
      builder: (all) {
        final rows = all
            .where((m) => _period?.contains(m.localDate) ?? true)
            .toList();
        rows.sort((a, b) {
          final date = b.localDate.compareTo(a.localDate);
          if (date != 0) return date;
          final band = a.band.index.compareTo(b.band.index);
          if (band != 0) return band;
          final time = b.measuredAtUtc.compareTo(a.measuredAtUtc);
          return time != 0 ? time : a.id.compareTo(b.id);
        });
        final stats = MeasurementStats(rows);
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_period != null)
                    Wrap(
                      children: [
                        Text('${_period!.start} – ${_period!.end}'),
                        TextButton(
                          onPressed: () => setState(() => _period = null),
                          child: const Text('Tutte le date'),
                        ),
                      ],
                    ),
                  Text('${stats.count} letture · ${stats.days} giorni'),
                  if (stats.count > 0)
                    Text(
                      'Medie: ${stats.systolic.mean!.toStringAsFixed(1)} / ${stats.diastolic.mean!.toStringAsFixed(1)} mmHg · ${stats.pulse.mean!.toStringAsFixed(1)} bpm',
                    ),
                  const SizedBox(height: 16),
                  if (rows.isEmpty)
                    const EmptyState(
                      title: 'Nessuna misurazione',
                      message: 'Non ci sono letture nel periodo selezionato.',
                      icon: Icons.menu_book_outlined,
                    ),
                ],
              );
            }
            final m = rows[index - 1];
            final previous = index > 1 ? rows[index - 2] : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (previous == null ||
                      previous.localDate != m.localDate ||
                      previous.band != m.band)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${m.localDate.split('-').reversed.join('/')} · ${TimeBand.values[m.band.index].label}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ReadingCard(
                    m,
                    onOpen: () => context.push('/measurement/${m.id}'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class ReadingDetailPage extends ConsumerWidget {
  final String id;
  const ReadingDetailPage(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Dettaglio lettura'),
      leading: BackButton(onPressed: () => context.pop()),
    ),
    body: ArchiveState(
      builder: (rows) {
        final matches = rows.where((m) => m.id == id);
        if (matches.isEmpty) {
          return const Center(
            child: Text('La lettura non è più presente nel diario.'),
          );
        }
        final m = matches.first;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ReadingCard(m),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/edit', extra: m),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifica lettura'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Elimina lettura'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final repo = await ref.read(
                    measurementRepositoryProvider.future,
                  );
                  await repo.delete(m);
                  if (!context.mounted) return;
                  context.pop();
                  Future<void> retryRestore() async {
                    try {
                      await repo.restore(m);
                    } catch (_) {
                      messenger.showSnackBar(
                        SnackBar(
                          duration: const Duration(minutes: 1),
                          content: const Text(
                            'Ripristino non riuscito. Libera spazio e riprova.',
                          ),
                          action: SnackBarAction(
                            label: 'Riprova',
                            onPressed: retryRestore,
                          ),
                        ),
                      );
                    }
                  }

                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 12),
                      content: const Text('Lettura eliminata'),
                      action: SnackBarAction(
                        label: 'Annulla',
                        onPressed: retryRestore,
                      ),
                    ),
                  );
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Eliminazione non riuscita. I dati sono conservati.',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    ),
  );
}
