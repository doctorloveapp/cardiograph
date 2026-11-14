import 'seven_segment.dart';

/// Relative to the CameraX shared viewport, after cropRect and rotationDegrees.
abstract final class CameraGuide {
  static const previousFraction = .76;
  static const scale = .70;
  static const fraction = previousFraction * scale;
  static const crop = DisplayCrop(
    (1 - fraction) / 2,
    (1 - fraction) / 2,
    (1 + fraction) / 2,
    (1 + fraction) / 2,
  );
}
