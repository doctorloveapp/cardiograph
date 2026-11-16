import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/design_system/components.dart';

class ZoomChartCard extends StatefulWidget {
  final String title;
  final Widget legend;
  final LineChartData data;
  final ValueChanged<bool> onInteraction;
  const ZoomChartCard({
    super.key,
    required this.title,
    required this.legend,
    required this.data,
    required this.onInteraction,
  });
  @override
  State<ZoomChartCard> createState() => _ZoomChartCardState();
}

class _ZoomChartCardState extends State<ZoomChartCard> {
  final controller = TransformationController();
  bool zoomed = false;
  Offset? origin;
  bool dragged = false;
  int? pointer;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  widget.legend,
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              height: 48,
              child: TextButton(
                key: const ValueKey('chart-zoom-toggle'),
                onPressed: () => setState(() {
                  zoomed = !zoomed;
                  controller.value = Matrix4.identity();
                }),
                child: Text(zoomed ? '1X' : '2X'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 270,
          child: LayoutBuilder(
            builder: (context, box) {
              if (zoomed && controller.value.getMaxScaleOnAxis() == 1) {
                controller.value = Matrix4.diagonal3Values(2, 2, 1)
                  ..setTranslationRaw(-box.maxWidth / 2, -box.maxHeight / 2, 0);
              }
              return Listener(
                onPointerDown: (event) {
                  if (zoomed && pointer == null) {
                    pointer = event.pointer;
                    origin = event.position;
                    dragged = false;
                    widget.onInteraction(true);
                  }
                },
                onPointerMove: (event) {
                  if (!zoomed || pointer != event.pointer || origin == null) {
                    return;
                  }
                  final movement = event.position - origin!;
                  if (!dragged && movement.distance < 8) return;
                  final delta = dragged ? event.delta : movement;
                  dragged = true;
                  final translation = controller.value.getTranslation();
                  controller.value = Matrix4.diagonal3Values(2, 2, 1)
                    ..setTranslationRaw(
                      (translation.x + delta.dx)
                          .clamp(-box.maxWidth, 0)
                          .toDouble(),
                      (translation.y + delta.dy)
                          .clamp(-box.maxHeight, 0)
                          .toDouble(),
                      0,
                    );
                },
                onPointerUp: (event) {
                  if (event.pointer == pointer) {
                    pointer = null;
                    origin = null;
                    scheduleMicrotask(() {
                      if (mounted) widget.onInteraction(false);
                    });
                  }
                },
                onPointerCancel: (event) {
                  if (event.pointer == pointer) {
                    pointer = null;
                    origin = null;
                    scheduleMicrotask(() {
                      if (mounted) widget.onInteraction(false);
                    });
                  }
                },
                child: LineChart(
                  widget.data,
                  duration: Duration.zero,
                  transformationConfig: FlTransformationConfig(
                    scaleAxis: zoomed ? FlScaleAxis.free : FlScaleAxis.none,
                    minScale: 1,
                    maxScale: 2,
                    scaleEnabled: false,
                    panEnabled: false,
                    transformationController: controller,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Reads the lock synchronously, before the next UI frame. Prevents the outer
/// scrollable consuming even the first drag delta or starting a fling on release.
class ChartScrollPhysics extends ClampingScrollPhysics {
  final ValueNotifier<bool> locked;
  const ChartScrollPhysics(this.locked, {super.parent});
  @override
  ChartScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ChartScrollPhysics(locked, parent: buildParent(ancestor));
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      locked.value ? 0 : super.applyPhysicsToUserOffset(position, offset);
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) =>
      locked.value ? null : super.createBallisticSimulation(position, velocity);
}
