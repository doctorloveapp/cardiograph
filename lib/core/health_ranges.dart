/// Categories configured for this diary; no stored or imported classifications.
enum PressureRange {
  low('Ipotensione', 0xff3b82f6, 1),
  normal('Normale', 0xff10b981, 0),
  grade1('Ipertensione Grado 1 (Lieve)', 0xfff59e0b, 2),
  grade2('Ipertensione Grado 2 (Moderata)', 0xfff97316, 3),
  grade3('Ipertensione Grado 3 (Grave)', 0xffef4444, 4);

  final String label;
  final int hex, priority;
  const PressureRange(this.label, this.hex, this.priority);
}

enum PulseRange {
  low('Bradicardia', 0xff3b82f6),
  normal('Normale', 0xff10b981),
  high('Tachicardia', 0xffef4444);

  final String label;
  final int hex;
  const PulseRange(this.label, this.hex);
}

PressureRange pressureRange(num systolic, num diastolic) {
  if (systolic >= 160 || diastolic >= 100) return PressureRange.grade3;
  if (systolic >= 140 || diastolic >= 90) return PressureRange.grade2;
  if (systolic >= 130 || diastolic >= 85) return PressureRange.grade1;
  if (systolic < 90 || diastolic < 60) return PressureRange.low;
  return PressureRange.normal;
}

PressureRange systolicRange(num value) => pressureRange(value, 70);
PressureRange diastolicRange(num value) => pressureRange(110, value);
PulseRange pulseRange(num value) => value >= 100
    ? PulseRange.high
    : value < 60
    ? PulseRange.low
    : PulseRange.normal;

class PressureDistribution {
  final Map<PressureRange, int> counts;
  final int total;
  PressureDistribution(Iterable<PressureRange> values)
    : this._(values.toList());
  PressureDistribution._(List<PressureRange> values)
    : total = values.length,
      counts = {
        for (final r in PressureRange.values)
          r: values.where((v) => v == r).length,
      };
  double percent(PressureRange r) => total == 0 ? 0 : 100 * counts[r]! / total;
}

const pressureLegend =
    'Ipotensione: SYS <90 o DIA <60, dopo i gradi ipertensivi. Normale: SYS 90–129 e DIA 60–84. Grado 1: SYS ≥130 o DIA ≥85; Grado 2: SYS ≥140 o DIA ≥90; Grado 3: SYS ≥160 o DIA ≥100. Prevale il grado più alto.';
const pulseLegend =
    'Bradicardia <60 bpm · Normale 60–99 bpm · Tachicardia ≥100 bpm.';

extension PressureCompactLegend on PressureRange {
  String get compactLabel => switch (this) {
    PressureRange.low => 'Ipotensione · <90 / <60',
    PressureRange.normal => 'Normale · 90–129 / 60–84',
    PressureRange.grade1 => 'Grado 1 · 130–139 / 85–89',
    PressureRange.grade2 => 'Grado 2 · 140–159 / 90–99',
    PressureRange.grade3 => 'Grado 3 · ≥160 / ≥100',
  };
}
