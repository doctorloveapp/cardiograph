import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  runApp(const ProviderScope(child: CardioGraphApp()));
}
