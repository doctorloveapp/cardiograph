import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/contracts.dart';

final clockProvider = Provider<AppClock>((ref) => const SystemClock());

class OpaqueController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final opaqueProvider = NotifierProvider<OpaqueController, bool>(
  OpaqueController.new,
);
