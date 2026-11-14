import '../vision/seven_segment.dart';

abstract interface class AppClock {
  DateTime now();
}

class SystemClock implements AppClock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class CapturedImage {
  final String path;
  final DateTime capturedAt;
  final String zone, timestampSource;
  final int offsetMinutes;
  final bool precise;
  final int width, height;
  const CapturedImage(
    this.path,
    this.capturedAt, {
    this.zone = 'UTC',
    this.offsetMinutes = 0,
    this.timestampSource = 'UNKNOWN',
    this.precise = false,
    this.width = 3,
    this.height = 4,
  });
}

class OcrCandidate {
  final int? systolic, diastolic, pulse;
  final DisplayReading? display;
  const OcrCandidate({this.systolic, this.diastolic, this.pulse, this.display});
}

abstract interface class CaptureService {
  Future<CapturedImage> capture();
}

abstract interface class OcrService {
  Future<OcrCandidate> recognize(CapturedImage image, {DisplayCrop? crop});
}

abstract interface class ReminderScheduler {
  Future<void> reconcile();
  Future<void> cancelAll();
}

abstract interface class DocumentFileService {
  Future<List<int>?> openBackup();
  Future<bool> save(String name, List<int> bytes);
}

abstract interface class KeyStoreService {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FeatureUnavailable implements Exception {
  final String message;
  const FeatureUnavailable(this.message);
}
