import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../vision/seven_segment.dart';
import 'contracts.dart';

class NativeCaptureService implements CaptureService {
  static const channel = MethodChannel('dev.danking.cardiograph/camera');
  final _errors = StreamController<String>.broadcast();
  NativeCaptureService() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'cameraError' && !_errors.isClosed) {
        _errors.add(call.arguments as String);
      }
    });
  }
  Stream<String> get errors => _errors.stream;
  void dispose() {
    channel.setMethodCallHandler(null);
    unawaited(_errors.close());
  }

  Future<String> permission({bool request = false}) async =>
      await channel.invokeMethod<String>(
        request ? 'requestPermission' : 'permission',
      ) ??
      'denied';
  Future<void> settings() => channel.invokeMethod('settings');
  Future<bool> start() async {
    final map = await channel.invokeMapMethod<String, dynamic>('start');
    return map?['torch'] == true;
  }

  Future<bool> torch(bool value) async =>
      await channel.invokeMethod<bool>('torch', {'enabled': value}) ?? false;
  Future<void> close() => channel.invokeMethod('close');
  @override
  Future<CapturedImage> capture() async {
    final m = (await channel.invokeMapMethod<String, dynamic>('capture'))!;
    return CapturedImage(
      m['path'] as String,
      DateTime.fromMillisecondsSinceEpoch(m['capturedAt'] as int, isUtc: true),
      zone: m['zone'] as String,
      offsetMinutes: m['offsetMinutes'] as int,
      precise: m['precise'] as bool,
      timestampSource: m['source'] as String,
      width: m['width'] as int,
      height: m['height'] as int,
    );
  }
}

DisplayReading _decodePhoto((String, DisplayCrop?) request) =>
    decodeDisplay(File(request.$1).readAsBytesSync(), crop: request.$2);

class SevenSegmentOcrService implements OcrService {
  @override
  Future<OcrCandidate> recognize(
    CapturedImage image, {
    DisplayCrop? crop,
  }) async {
    final display = await compute(_decodePhoto, (image.path, crop));
    return OcrCandidate(
      systolic: display.values[0],
      diastolic: display.values[1],
      pulse: display.values[2],
      display: display,
    );
  }
}

/// Only dedicated camera cache files may be deleted. No recursive deletion.
class TemporaryPhotoStore {
  final Directory directory;
  const TemporaryPhotoStore(this.directory);
  static Future<TemporaryPhotoStore> device() async => TemporaryPhotoStore(
    Directory('${(await getTemporaryDirectory()).path}/cardiograph_camera'),
  );
  Future<void> delete(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final canonical = File(await file.resolveSymbolicLinks());
    final root = await directory.resolveSymbolicLinks();
    if (canonical.parent.path != root ||
        !canonical.uri.pathSegments.last.startsWith('frame_')) {
      throw const FileSystemException('File esterno alla cache fotografica');
    }
    await canonical.delete();
  }
}

final captureServiceProvider = Provider<NativeCaptureService>((ref) {
  final service = NativeCaptureService();
  ref.onDispose(service.dispose);
  return service;
});
final ocrServiceProvider = Provider<OcrService>(
  (ref) => SevenSegmentOcrService(),
);
final photoStoreProvider = FutureProvider<TemporaryPhotoStore>(
  (ref) => TemporaryPhotoStore.device(),
);
