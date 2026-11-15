import 'reminder_sync.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_system/components.dart';
import '../../core/services/contracts.dart';
import '../../core/services/platform_services.dart';
import '../../data/providers.dart';
import '../backup/backup_service.dart';

class ReminderStatus {
  final bool allowed, exact;
  final String zone;
  final List<Map<String, dynamic>> slots;
  ReminderStatus(Map<String, dynamic> m)
    : allowed = m['allowed'] == true,
      exact = m['exact'] == true,
      zone = m['zone'] as String,
      slots = (m['slots'] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
}

class AndroidReminderScheduler implements ReminderScheduler {
  static const channel = AndroidDocumentFileService.channel;
  Future<ReminderStatus> status() async => ReminderStatus(
    (await channel.invokeMapMethod<String, dynamic>('reminderStatus'))!,
  );
  Future<ReminderStatus> enable(int id, bool enabled) async {
    if (enabled) await channel.invokeMethod('requestNotifications');
    return ReminderStatus(
      (await channel.invokeMapMethod<String, dynamic>('setReminder', {
        'id': id,
        'enabled': enabled,
      }))!,
    );
  }

  Future<void> test() async {
    await channel.invokeMethod('requestNotifications');
    await channel.invokeMethod('testNotification');
  }

  @override
  Future<void> reconcile() => channel.invokeMethod('reconcile');
  @override
  Future<void> cancelAll() async {
    for (final id in [1000, 1600, 2100]) {
      await enable(id, false);
    }
  }
}

final reminderSchedulerProvider = Provider<AndroidReminderScheduler>(
  (ref) => AndroidReminderScheduler(),
);

class ReminderSettings extends ConsumerStatefulWidget {
  const ReminderSettings({super.key});
  @override
  ConsumerState<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<ReminderSettings>
    with WidgetsBindingObserver {
  ReminderStatus? _status;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final status = await ref.read(reminderSchedulerProvider).status();
      if (mounted) setState(() => _status = status);
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Disponibile su Android');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossibile leggere lo stato dei promemoria');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Operazione non riuscita');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Operazione non riuscita. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSettingsProvider, (previous, next) {
      if (next.hasValue) unawaited(_refresh());
    });
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Promemoria giornalieri',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ti avvisiamo solo se manca una lettura nella sessione. Gli orari seguono il fuso del telefono.',
          ),
          for (final (i, id, name) in [
            (0, 1000, 'Mattina'),
            (1, 1600, 'Pomeriggio'),
            (2, 2100, 'Sera'),
          ]) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: ValueKey('reminder-$id'),
              title: Text(name),
              subtitle: _status != null && _status!.slots[i]['enabled'] == true
                  ? Text(
                      _status!.allowed
                          ? 'Prossimo: ${_next(_status!.slots[i]['next'] as String)}'
                          : 'Attivo, notifiche bloccate da Android',
                    )
                  : null,
              value: _status?.slots[i]['enabled'] == true,
              onChanged: _busy || _status == null
                  ? null
                  : (enabled) => _run(() async {
                      if (enabled) {
                        await AndroidReminderScheduler.channel.invokeMethod(
                          'requestNotifications',
                        );
                      }
                      await (await ref.read(
                        backupServiceProvider.future,
                      )).setReminder(id, enabled);
                    }),
            ),
            OutlinedButton.icon(
              key: ValueKey('reminder-time-$id'),
              icon: const Icon(Icons.schedule),
              label: Text(
                'Orario $name: ${reminderTime((_status?.slots[i]['minutes'] as int?) ?? [600, 960, 1260][i])}',
              ),
              onPressed: _busy || _status == null
                  ? null
                  : () async {
                      final current = _status!.slots[i]['minutes'] as int;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: current ~/ 60,
                          minute: current % 60,
                        ),
                        helpText: [
                          'Mattina · 07:00–13:00',
                          'Pomeriggio · 13:01–19:00',
                          'Sera · 19:01–06:59',
                        ][i],
                        builder: (c, child) => MediaQuery(
                          data: MediaQuery.of(
                            c,
                          ).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                      );
                      if (time == null || !mounted) return;
                      final minutes = time.hour * 60 + time.minute;
                      if (!validReminderMinute(i, minutes)) {
                        setState(
                          () => _error = [
                            'Scegli un orario tra 07:00 e 13:00.',
                            'Scegli un orario tra 13:01 e 19:00.',
                            'Scegli un orario tra 19:01 e 06:59.',
                          ][i],
                        );
                        return;
                      }
                      await _run(
                        () async => (await ref.read(
                          backupServiceProvider.future,
                        )).setReminderTime(id, minutes),
                      );
                    },
            ),
            const SizedBox(height: 8),
          ],
          if (_status?.slots.any((s) => s['pendingSync'] == true) == true)
            const Text(
              'Sincronizzazione promemoria da completare: riapri la schermata per riprovare.',
            ),
          if (_status != null) ...[
            Text(
              _status!.allowed
                  ? 'Notifiche consentite'
                  : 'Notifiche non consentite: abilita app e canale nelle impostazioni Android.',
            ),
            const SizedBox(height: 6),
            Text(
              _status!.exact
                  ? 'Precisione: consentita'
                  : 'I promemoria possono arrivare in ritardo',
            ),
            Text('Fuso corrente: ${_status!.zone}'),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, semanticsLabel: _error),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => AndroidReminderScheduler.channel.invokeMethod(
                      'notificationSettings',
                    ),
                  ),
            child: const Text('Impostazioni notifiche Android'),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => AndroidReminderScheduler.channel.invokeMethod(
                      'exactSettings',
                    ),
                  ),
            child: const Text('Consenti promemoria precisi'),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await ref.read(reminderSchedulerProvider).test();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Notifica di prova inviata'),
                        ),
                      );
                    }
                  }),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Invia notifica di prova'),
          ),
        ],
      ),
    );
  }

  String _next(String value) {
    final date = value.split('T').first.split('-').reversed.join('/');
    return '$date ${value.split('T').last.substring(0, 5)}';
  }
}
