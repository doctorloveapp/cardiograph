import '../data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/contracts.dart';

final clockProvider = Provider<AppClock>((ref) => const SystemClock());

class OpaqueController extends Notifier<bool> {
  @override
  bool build() => false;
  Future<void> set(bool value) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.update((p) => p.copyWith(opaque: value));
    state = value;
    ref.invalidate(appSettingsProvider);
  }
}

final opaqueProvider = NotifierProvider<OpaqueController, bool>(
  OpaqueController.new,
);
