import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/health_ranges.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/theme.dart';
import '../measurements/measurement.dart';

class PressurePie extends StatelessWidget {
  final List<Measurement> rows;
  const PressurePie(this.rows, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = PressureDistribution(rows.map((r) => r.pressureCategory));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Distribuzione pressione',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (d.total == 0)
            const Text('Nessuna misurazione nel periodo')
          else
            SizedBox(
              height: 200,
              child: Semantics(
                label:
                    'Distribuzione di ${d.total} misurazioni. Conteggi e percentuali nella legenda.',
                child: ExcludeSemantics(
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 30,
                      sectionsSpace: 2,
                      sections: [
                        for (final r in PressureRange.values)
                          if (d.counts[r]! > 0)
                            PieChartSectionData(
                              value: d.counts[r]!.toDouble(),
                              color: Color(r.hex),
                              showTitle: true,
                              title: '${d.percent(r).toStringAsFixed(1)}%',
                              titleStyle: TextStyle(
                                color: Color(0xff071627),
                                fontSize: d.percent(r) < 5 ? 8 : 12,
                                fontWeight: FontWeight.w700,
                              ),
                              titlePositionPercentageOffset: d.percent(r) < 5
                                  ? .2 + .15 * r.index
                                  : .55,
                              radius: 65,
                            ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
                ),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final r in PressureRange.values)
                Semantics(
                  label:
                      '${r.label}: ${d.counts[r]} letture, ${d.percent(r).toStringAsFixed(1)} per cento',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Color(r.hex),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          r.compactLabel,
                          style: const TextStyle(
                            color: Brand.navy,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
