import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

class GlassDialog extends AlertDialog {
  const GlassDialog({super.key, super.title, super.content, super.actions});
  @override
  Widget build(BuildContext context) {
    final opaque =
        Theme.of(context).extension<SurfaceStyle>()!.opaque ||
        MediaQuery.of(context).accessibleNavigation;
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: opaque ? 0 : Brand.blur,
        sigmaY: opaque ? 0 : Brand.blur,
      ),
      child: super.build(context),
    );
  }
}

class GlassSheet extends StatelessWidget {
  final Widget child;
  const GlassSheet({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final opaque =
        Theme.of(context).extension<SurfaceStyle>()!.opaque ||
        MediaQuery.of(context).accessibleNavigation;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: opaque ? 0 : Brand.blur,
          sigmaY: opaque ? 0 : Brand.blur,
        ),
        child: child,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final opaque =
        Theme.of(context).extension<SurfaceStyle>()!.opaque ||
        MediaQuery.of(context).accessibleNavigation;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Brand.navy.withValues(alpha: opaque ? .08 : .14),
            blurRadius: 24,
            offset: const Offset(5, 10),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 5,
            offset: Offset(-2, -3),
          ),
        ],
      ),
      child: ClipRRect(
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
              color: opaque ? Colors.white : null,
              gradient: opaque
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .93),
                        Colors.white.withValues(alpha: .72),
                      ],
                    ),
              borderRadius: BorderRadius.circular(Brand.cardRadius),
              border: Border.all(
                color: opaque
                    ? Brand.navy.withValues(alpha: .25)
                    : Colors.white,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The colored light lives below the glass, including full-screen routes.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xffcceafb),
          Brand.canvas,
          Color(0xffd7f4ed),
          Color(0xffd9eafb),
        ],
        stops: [0, .4, .73, 1],
      ),
    ),
    child: child,
  );
}

class GlassNavigationSurface extends StatelessWidget {
  final Widget child;
  const GlassNavigationSurface({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final opaque =
        Theme.of(context).extension<SurfaceStyle>()!.opaque ||
        MediaQuery.of(context).accessibleNavigation;
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Brand.navy.withValues(alpha: .15),
            blurRadius: 24,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: opaque ? 0 : Brand.blur,
            sigmaY: opaque ? 0 : Brand.blur,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: opaque
                    ? [const Color(0xffcce6f6), const Color(0xffdceefa)]
                    : [
                        Brand.sky.withValues(alpha: .40),
                        const Color(0xffd5eafa).withValues(alpha: .94),
                      ],
              ),
              border: const Border(
                top: BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: child,
          ),
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
  final VoidCallback? onPressed;
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
