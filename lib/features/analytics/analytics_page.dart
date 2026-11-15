import '../../core/text/italian.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/components.dart';
import '../../core/time/measurement_time.dart';
import '../../data/providers.dart';
import '../measurements/diary.dart';
import 'analytics_model.dart';
import '../measurements/measurement.dart';

Color metricColor(Metric metric, num value) => metric.high(value)
    ? Brand.red
    : switch (metric) {
        Metric.systolic => Brand.blue,
        Metric.diastolic => Brand.ink,
        Metric.pulse => Brand.navy,
      };

/// Straight observation-to-observation segments. No synthetic dates or zeroes.
LineChartData metricChart(
  AnalyticsData data,
  List<Metric> metrics,
  void Function(ChartObservation) select,
) {
  final observations = data.observations;
  final descriptors = [
    for (final metric in metrics)
      for (final kind in (data.aggregated ? [0, 1, 2] : [0])) (metric, kind),
  ];
  final bars = descriptors.map((d) {
    final metric = d.$1, kind = d.$2;
    final spots = observations.map((o) {
      final stats = o.stats(metric);
      return FlSpot(
        o.x,
        kind == 1
            ? stats.minimum!.toDouble()
            : kind == 2
            ? stats.maximum!.toDouble()
            : stats.mean!,
      );
    }).toList();
    final color = metric == Metric.systolic
        ? Brand.blue
        : metric == Metric.diastolic
        ? Brand.ink
        : Brand.navy;
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color.withValues(alpha: kind == 0 ? 1 : .45),
      barWidth: kind == 0 ? 2.5 : 1,
      dashArray: kind != 0
          ? [3, 4]
          : metric == Metric.diastolic
          ? [7, 4]
          : null,
      belowBarData: BarAreaData(show: false),
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, p, bar, index) => metric == Metric.diastolic
            ? FlDotSquarePainter(
                size: kind == 0 ? 7 : 5,
                color: metricColor(metric, spot.y),
                strokeWidth: 0,
              )
            : FlDotCirclePainter(
                radius: kind == 0 ? 3.5 : 2.5,
                color: metricColor(metric, spot.y),
                strokeWidth: 0,
              ),
      ),
    );
  }).toList();
  final ys = [
    for (final bar in bars)
      for (final spot in bar.spots) spot.y,
    for (final m in metrics) m.threshold.toDouble(),
  ];
  final intraday =
      !data.aggregated && observations.first.day == observations.last.day;
  final span = observations.last.x - observations.first.x;
  final padding = observations.length == 1
      ? (intraday ? 1 / 24 : .5)
      : intraday
      ? math.max(1 / 24, span * .08)
      : .3;
  final xInterval = observations.length == 1
      ? (intraday ? 1 / 24 : .5)
      : intraday
      ? math.max(1 / 24, span / 3)
      : math.max(1, span / 3);
  final lower =
      (math.max(0, ys.reduce(math.min) - 12) / 10).floorToDouble() * 10;
  final upper = ((ys.reduce(math.max) + 12) / 10).ceilToDouble() * 10;
  return LineChartData(
    minX: observations.first.x - padding,
    maxX: observations.last.x + padding,
    minY: lower,
    maxY: upper,
    clipData: const FlClipData.all(),
    borderData: FlBorderData(show: false),
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          minIncluded: false,
          maxIncluded: false,
          interval: math.max(10, ((upper - lower) / 50).ceilToDouble() * 10),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          minIncluded: false,
          maxIncluded: false,
          interval: xInterval.toDouble(),
          getTitlesWidget: (value, meta) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              DateFormat(intraday ? 'HH:mm' : 'dd/MM').format(
                DateTime.fromMillisecondsSinceEpoch(
                  (value * 86400000).round(),
                  isUtc: true,
                ),
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ),
    ),
    extraLinesData: ExtraLinesData(
      horizontalLines: [
        for (final m in metrics)
          HorizontalLine(
            y: m.threshold.toDouble(),
            color: Brand.navy.withValues(alpha: .55),
            strokeWidth: 1,
            dashArray: [5, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              labelResolver: (_) => '${m.threshold}',
              style: const TextStyle(fontSize: 11, color: Brand.navy),
            ),
          ),
      ],
    ),
    lineBarsData: bars,
    lineTouchData: LineTouchData(
      distanceCalculator: (touch, spot) => (touch - spot).distance,
      getTouchedSpotIndicator: (bar, indexes) => indexes
          .map(
            (i) => TouchedSpotIndicatorData(
              FlLine(color: Brand.navy.withValues(alpha: .3), strokeWidth: 1),
              bar.dotData,
            ),
          )
          .toList(),
      touchCallback: (event, response) {
        if (event is FlTapUpEvent &&
            response?.lineBarSpots?.isNotEmpty == true) {
          select(observations[response!.lineBarSpots!.first.spotIndex]);
        }
      },
      touchTooltipData: LineTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        maxContentWidth: 220,
        getTooltipColor: (_) => Colors.white,
        getTooltipItems: (spots) => spots.map((s) {
          final observation = observations[s.spotIndex],
              d = descriptors[s.barIndex];
          final row = observation.originals.first;
          final date = observation.daily
              ? '${observation.day} · ${countNoun(observation.originals.length, 'lettura', 'letture')}'
              : '${row.localDate} ${row.localTime}\n${row.zone} · UTC${row.offsetMinutes >= 0 ? '+' : '-'}${(row.offsetMinutes.abs() ~/ 60).toString().padLeft(2, '0')}:${(row.offsetMinutes.abs() % 60).toString().padLeft(2, '0')}';
          return LineTooltipItem(
            '$date\n${d.$1.label}${data.aggregated ? ' · ${['media', 'min', 'max'][d.$2]}' : ''}: ',
            const TextStyle(
              color: Brand.navy,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            children: [
              TextSpan(
                text: s.y.toStringAsFixed(1),
                style: TextStyle(color: metricColor(d.$1, s.y)),
              ),
              TextSpan(text: ' ${d.$1.unit}'),
            ],
          );
        }).toList(),
      ),
    ),
  );
}

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});
  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  int _days = 7, _shown = 20;
  CivilPeriod? _custom;
  bool _all = false;
  DayBand? _band;
  String? _selectedId, _selectedDay;
  Future<void> _pick() async {
    final now = ref.read(clockProvider).now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 6)),
        end: now,
      ),
    );
    if (range != null && mounted) {
      setState(() {
        _all = false;
        _custom = CivilPeriod(dateKey(range.start), dateKey(range.end));
        _shown = 20;
        _selectedId = null;
        _selectedDay = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).now();
    final period =
        _custom ??
        CivilPeriod(
          dateKey(DateTime.utc(now.year, now.month, now.day - _days + 1)),
          dateKey(now),
        );
    final readings = _all
        ? ref.watch(measurementsProvider)
        : ref.watch(periodReadingsProvider((period.start, period.end)));
    return readings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ErrorFeedback(
            message: 'Impossibile leggere l’andamento. Riprova.',
            onRetry: () => ref.invalidate(databaseProvider),
          ),
        ],
      ),
      data: (rows) {
        final selectedRows = rows
            .where((r) => _band == null || r.band == _band)
            .toList();
        final dates = selectedRows.map((r) => r.localDate).toList()..sort();
        final shownPeriod = _all && dates.isNotEmpty
            ? CivilPeriod(dates.first, dates.last)
            : period;
        final data = AnalyticsData(rows, period: shownPeriod, band: _band);
        final selected = data.rows
            .where(
              (r) => _selectedDay != null
                  ? r.localDate == _selectedDay
                  : r.id == _selectedId,
            )
            .toList();
        final originals = selected.isEmpty
            ? data.rows.reversed.toList()
            : selected;
        final count = math.min(_shown, originals.length);
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: count + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Andamento',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final days in [7, 30, 90])
                        ChoiceChip(
                          label: Text('$days giorni'),
                          selected: !_all && _custom == null && _days == days,
                          onSelected: (_) => setState(() {
                            _all = false;
                            _days = days;
                            _custom = null;
                            _shown = 20;
                            _selectedId = null;
                            _selectedDay = null;
                          }),
                        ),
                      ChoiceChip(
                        label: const Text('Tutte le misurazioni'),
                        selected: _all,
                        onSelected: (_) => setState(() {
                          _all = true;
                          _custom = null;
                          _shown = 20;
                          _selectedId = null;
                          _selectedDay = null;
                        }),
                      ),
                      ActionChip(
                        label: const Text('Intervallo personalizzato'),
                        onPressed: _pick,
                      ),
                    ],
                  ),
                  Text(
                    _all && dates.isEmpty
                        ? 'Archivio senza letture per questo filtro'
                        : '${shownPeriod.start} – ${shownPeriod.end}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Tutte'),
                        selected: _band == null,
                        onSelected: (_) => setState(() {
                          _band = null;
                          _shown = 20;
                          _selectedId = null;
                          _selectedDay = null;
                        }),
                      ),
                      for (final band in DayBand.values)
                        ChoiceChip(
                          label: Text(TimeBand.values[band.index].label),
                          selected: _band == band,
                          onSelected: (_) => setState(() {
                            _band = band;
                            _shown = 20;
                            _selectedId = null;
                            _selectedDay = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data.rows.isEmpty)
                    const EmptyState(
                      title: 'Nessuna misurazione nel periodo',
                      message:
                          'Scegli un altro periodo o registra una lettura.',
                      icon: Icons.show_chart,
                    )
                  else ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '${countNoun(data.stats.count, 'lettura', 'letture')} · ${countNoun(data.stats.days, 'giorno', 'giorni')} con dati',
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Statistiche',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          for (final metric in Metric.values)
                            _MetricSummary(
                              metric,
                              MetricStats(data.rows.map(metric.value)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (data.aggregated)
                      const Text(
                        'Aggregazione giornaliera: media con linee min/max tratteggiate. I massimi restano visibili; nessun giorno vuoto è riempito. Le singole letture sono disponibili sotto.',
                      )
                    else
                      const Text(
                        'Ogni punto è una lettura. Le linee rette collegano osservazioni, senza stimare misure nei giorni vuoti.',
                      ),
                    const SizedBox(height: 16),
                    for (final metrics in [
                      [Metric.systolic, Metric.diastolic],
                      [Metric.pulse],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metrics.length == 2
                                    ? 'Pressione · mmHg'
                                    : 'Pulsazioni · bpm',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Wrap(
                                spacing: 16,
                                children: [
                                  for (final m in metrics)
                                    Text(
                                      '${m == Metric.diastolic ? '■ ┄' : '● ━'} ${m.label}',
                                      style: TextStyle(
                                        color: metricColor(m, 0),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Semantics(
                                label:
                                    '${metrics.length == 2 ? 'Grafico pressione' : 'Grafico pulsazioni'}, ${countNoun(data.stats.count, 'lettura', 'letture')}. Riepilogo e letture originali disponibili sotto.',
                                child: SizedBox(
                                  height: 270,
                                  child: LineChart(
                                    metricChart(
                                      data,
                                      metrics,
                                      (o) => setState(() {
                                        _selectedId = o.daily
                                            ? null
                                            : o.originals.first.id;
                                        _selectedDay = o.daily ? o.day : null;
                                        _shown = 20;
                                      }),
                                    ),
                                    duration: Duration.zero,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      selected.isEmpty
                          ? 'Letture originali'
                          : 'Selezione dal grafico',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedDay = null;
                          _selectedId = null;
                          _shown = 20;
                        }),
                        child: const Text('Mostra tutte le letture'),
                      ),
                    Text(
                      '$count di ${countNoun(originals.length, 'lettura', 'letture')} · tocca Apri lettura per dettaglio e modifica',
                    ),
                  ],
                ],
              );
            }
            if (index == count + 1) {
              return count < originals.length
                  ? TextButton(
                      onPressed: () => setState(() => _shown += 20),
                      child: const Text('Mostra altre 20 letture'),
                    )
                  : const SizedBox(height: 16);
            }
            final m = originals[index - 1];
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ReadingCard(
                m,
                onOpen: () => context.push('/measurement/${m.id}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _MetricSummary extends StatelessWidget {
  final Metric metric;
  final MetricStats stats;
  const _MetricSummary(this.metric, this.stats);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${metric.label} · ${metric.unit}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final entry in [
              ('Media', stats.mean!),
              ('Min', stats.minimum!),
              ('Max', stats.maximum!),
            ])
              Semantics(
                label:
                    '${metric.label}, ${entry.$1} ${entry.$2.toStringAsFixed(1)} ${metric.unit}${metric.high(entry.$2) ? ', oltre soglia' : ''}',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    text: '${entry.$1} ',
                    style: const TextStyle(
                      color: Brand.navy,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: entry.$2.toStringAsFixed(1),
                        style: TextStyle(color: metricColor(metric, entry.$2)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
