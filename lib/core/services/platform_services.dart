import 'package:flutter/services.dart';
import 'contracts.dart';

class AndroidDocumentFileService implements DocumentFileService {
  static const channel = MethodChannel('dev.danking.cardiograph/platform');
  @override
  Future<List<int>?> openBackup() =>
      channel.invokeMethod<Uint8List>('openBackup');
  @override
  Future<bool> save(String name, List<int> bytes) async =>
      await channel.invokeMethod<bool>('save', {
        'name': name,
        'bytes': Uint8List.fromList(bytes),
      }) ??
      false;
  Future<void> share(Uint8List bytes) =>
      channel.invokeMethod('share', {'bytes': bytes});
}
