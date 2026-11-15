import 'dart:io';
import 'package:flutter/services.dart';
import '../../data/repositories.dart';
import '../../core/services/platform_services.dart';
import '../../core/time/measurement_time.dart';

const reminderIds = [1000, 1600, 2100];
bool validReminderMinute(int index, int minute) =>
    minute >= 0 &&
    minute < 1440 &&
    bandFor(DateTime.utc(2000, 1, 1, minute ~/ 60, minute % 60)).index == index;
String reminderTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class ReminderSync {
  final MeasurementRepository repository;
  ReminderSync(this.repository);
  static const channel = AndroidDocumentFileService.channel;
  static Future<void> begin({bool forceForTest = false}) async {
    if (!Platform.isAndroid && !forceForTest) return;
    try {
      await channel.invokeMethod('beginReminderMutation');
    } on MissingPluginException {
      /* Non-Android tests. */
    }
  }

  Future<void> apply({bool forceForTest = false}) async {
    if (!Platform.isAndroid && !forceForTest) return;
    final prefs = await SettingsRepository(repository.db).read();
    final coverage = await repository.reminderCoverage();
    try {
      await channel.invokeMethod('applyReminderPreferences', {
        'enabled': prefs.reminders,
        'minutes': prefs.reminderMinutes,
        'coverage': coverage,
      });
    } on MissingPluginException {
      /* Non-Android tests. */
    }
  }
}
