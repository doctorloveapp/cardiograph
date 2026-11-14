import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final opaque =
        Theme.of(context).extension<SurfaceStyle>()!.opaque ||
        MediaQuery.of(context).accessibleNavigation;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: opaque ? 0 : Brand.blur,
          sigmaY: opaque ? 0 : Brand.blur,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opaque ? 1 : .92),
            borderRadius: BorderRadius.circular(Brand.cardRadius),
            border: Border.all(
              color: opaque ? Brand.navy.withValues(alpha: .25) : Colors.white,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class MeasurementValue extends StatelessWidget {
  final String label, unit;
  final int? value;
  final bool elevated;
  const MeasurementValue({
    super.key,
    required this.label,
    required this.unit,
    this.value,
    this.elevated = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label: ${value ?? "nessun dato"} $unit${elevated ? ", oltre soglia" : ""}',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          value?.toString() ?? '—',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: elevated ? Brand.red : Brand.navy,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(unit),
      ],
    ),
  );
}

enum TimeBand {
  morning('Mattina', Icons.wb_sunny_outlined),
  afternoon('Pomeriggio', Icons.light_mode_outlined),
  evening('Sera', Icons.nights_stay_outlined);

  const TimeBand(this.label, this.icon);
  final String label;
  final IconData icon;
}

class TimeBandBadge extends StatelessWidget {
  final TimeBand band;
  const TimeBandBadge(this.band, {super.key});
  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(band.icon, size: 18, color: Brand.ink),
    label: Text(band.label),
    backgroundColor: Brand.soft,
    side: BorderSide.none,
  );
}

class PrimaryAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.soft,
          ),
          child: Icon(icon, size: 36, color: Brand.ink),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class ErrorFeedback extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorFeedback({
    super.key,
    required this.message,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: GlassCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Brand.red),
          Text(message),
          TextButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    ),
  );
}
