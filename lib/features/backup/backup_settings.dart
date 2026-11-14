import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/services/platform_services.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import 'backup_codec.dart';
import 'backup_service.dart';

final documentFileServiceProvider = Provider<AndroidDocumentFileService>(
  (ref) => AndroidDocumentFileService(),
);

class RecoveryWarning extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final recoveryWarningProvider = NotifierProvider<RecoveryWarning, bool>(
  RecoveryWarning.new,
);

class BackupSettings extends ConsumerStatefulWidget {
  const BackupSettings({super.key});
  @override
  ConsumerState<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends ConsumerState<BackupSettings> {
  bool _busy = false;
  String? _progress, _error;
  final _filesKey = GlobalKey();
  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      setState(() => _error = null);
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is BackupFailure
              ? e.message
              : 'Operazione non riuscita. Le letture non vengono cancellate in caso di errore prima della conferma.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<String?> _password({required bool confirm}) async {
    final password = TextEditingController(), again = TextEditingController();
    String? error;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => GlassDialog(
            title: Text(confirm ? 'Proteggi il backup' : 'Password del backup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    confirm
                        ? 'Scegli almeno 8 caratteri. Conserva la password: sarà necessaria per ripristinare questo file.'
                        : 'Il file selezionato è cifrato. Inserisci la sua password.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 256,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  if (confirm)
                    TextField(
                      controller: again,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLength: 256,
                      decoration: const InputDecoration(
                        labelText: 'Conferma password',
                      ),
                    ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () {
                  if ((confirm &&
                          (password.text.runes.length < 8 ||
                              password.text != again.text)) ||
                      password.text.isEmpty) {
                    update(
                      () => error = confirm
                          ? 'Inserisci almeno 8 caratteri e una conferma identica.'
                          : 'Inserisci la password.',
                    );
                    return;
                  }
                  Navigator.pop(c, password.text);
                },
                child: const Text('Continua'),
              ),
            ],
          ),
        ),
      );
    } finally {
      password.clear();
      again.clear();
      password.dispose();
      again.dispose();
    }
  }

  Future<bool> _export() async {
    final service = await ref.read(backupServiceProvider.future);
    final archive = await service.snapshot();
    if (!mounted) return false;
    String? password;
    if (archive.settings.protectBackupWithPassword) {
      password = await _password(confirm: true);
      if (password == null) return false;
    }
    setState(
      () => _progress = password == null
          ? 'Preparazione backup…'
          : 'Cifratura del backup…',
    );
    final now = ref.read(clockProvider).now();
    final bytes = await compute(encodeBackupWorker, (archive, password, now));
    password = null;
    final stamp = now
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final saved = await ref
        .read(documentFileServiceProvider)
        .save('CardioGraph_$stamp.cardiograph', bytes);
    if (saved) {
      await service.markSuccessfulBackup(now);
      _message('Backup salvato · ${archive.rows.length} letture');
    } else {
      _message('Esportazione annullata');
    }
    return saved;
  }

  Future<void> _import() async {
    final bytes = await ref.read(documentFileServiceProvider).openBackup();
    if (bytes == null || !mounted) return;
    setState(() => _progress = 'Verifica del file…');
    final data = Uint8List.fromList(bytes);
    final encrypted = await compute(backupNeedsPassword, data);
    if (!mounted) return;
    String? password;
    if (encrypted) {
      password = await _password(confirm: false);
      if (password == null) return;
    }
    setState(
      () => _progress = encrypted
          ? 'Decifratura e validazione…'
          : 'Validazione del backup…',
    );
    final archive = await compute(decodeBackupWorker, (data, password));
    password = null;
    if (!mounted || !await _confirmReplace(archive)) return;
    setState(() => _progress = 'Ripristino dell’archivio…');
    final outcome = await (await ref.read(
      backupServiceProvider.future,
    )).replace(archive);
    ref.read(recoveryWarningProvider.notifier).set(outcome.remindersPending);
    _message(
      outcome.remindersPending
          ? 'Archivio ripristinato. Riconciliazione promemoria da completare.'
          : 'Archivio ripristinato · ${archive.rows.length} letture',
    );
  }

  Future<bool> _confirmReplace(BackupArchive archive) async {
    while (mounted) {
      final result = await showDialog<String>(
        context: context,
        builder: (c) => GlassDialog(
          title: const Text('Sostituisci l’archivio'),
          content: Text(
            '${archive.rows.length} letture${archive.firstDate == null ? '' : '\n${archive.firstDate} – ${archive.lastDate}'}\n\nIl ripristino sostituirà tutte le letture e le preferenze portabili correnti. Esporta prima una copia dell’archivio attuale.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('Annulla'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, 'backup'),
              child: const Text('Esporta prima'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'replace'),
              child: const Text('Sostituisci archivio'),
            ),
          ],
        ),
      );
      if (result == 'replace') return true;
      if (result != 'backup') return false;
      if (!await _export()) return false;
      if (!mounted) return false;
    }
    return false;
  }

  Future<void> _erase() async {
    final service = await ref.read(backupServiceProvider.future);
    final current = await service.snapshot();
    if (!mounted) return;
    final step = await showDialog<String>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Cancella tutti i dati'),
        content: Text(
          'Sono presenti ${current.rows.length} letture. Verranno cancellate insieme alle preferenze dell’app. I backup già esportati rimarranno nei percorsi scelti. Vuoi esportare prima un backup?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annulla'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(c, 'backup'),
            child: const Text('Esporta prima'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'continue'),
            child: const Text('Prosegui'),
          ),
        ],
      ),
    );
    if (step == null || (step == 'backup' && !await _export()) || !mounted) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Conferma cancellazione definitiva'),
        content: const Text(
          'Questa operazione svuoterà l’archivio e disattiverà i promemoria. Confermi di voler cancellare tutti i dati locali?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancella tutti i dati'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _progress = 'Cancellazione dell’archivio…');
    final result = await service.replace(
      BackupArchive([], const AppSettings()),
      erase: true,
    );
    ref.read(recoveryWarningProvider.notifier).set(result.remindersPending);
    _message(
      result.remindersPending
          ? 'Dati cancellati. Disattivazione promemoria da completare.'
          : 'Dati locali cancellati',
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appSettingsProvider);
    final settings = prefs.asData?.value;
    return PopScope(
      canPop: !_busy,
      child: GlassCard(
        key: _filesKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Backup e dati',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Il backup standard è leggibile da chi possiede il file. Attivando la protezione, le esportazioni future saranno cifrate con la password scelta.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Proteggi backup con password'),
              key: const ValueKey('protect-backup'),
              value: settings?.protectBackupWithPassword ?? false,
              onChanged: _busy || settings == null
                  ? null
                  : (value) => _run(() async {
                      final repo = await ref.read(
                        settingsRepositoryProvider.future,
                      );
                      await repo.update(
                        (p) => p.copyWith(protectBackupWithPassword: value),
                      );
                      ref.invalidate(appSettingsProvider);
                    }),
            ),
            if (settings?.lastBackupUtc != null)
              Text(
                'Ultimo backup riuscito: ${settings!.lastBackupUtc!.toLocal().toString().substring(0, 19)}',
              ),
            if (prefs.hasError)
              const Text(
                'Impossibile leggere le preferenze. Riapri Impostazioni.',
              ),
            if (ref.watch(recoveryWarningProvider)) ...[
              const Text(
                'Archivio già aggiornato. Resta da riconciliare i promemoria con Android.',
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final done = await (await ref.read(
                          backupServiceProvider.future,
                        )).recover();
                        ref.read(recoveryWarningProvider.notifier).set(!done);
                      }),
                child: const Text('Riprova promemoria'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || settings == null
                  ? null
                  : () => _run(() async {
                      await _export();
                    }),
              icon: const Icon(Icons.save_alt),
              label: const Text('Esporta backup'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || settings == null ? null : () => _run(_import),
              icon: const Icon(Icons.restore),
              label: const Text('Ripristina backup'),
            ),
            OutlinedButton(
              onPressed: _busy || settings == null ? null : () => _run(_erase),
              child: const Text('Cancella tutti i dati'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              Text(_progress ?? 'Operazione in corso…'),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, semanticsLabel: _error),
              ),
            const SizedBox(height: 8),
            const Text(
              'Formato .cardiograph · massimo 64 MiB e 100.000 letture. Il ripristino richiede la password solo per i file cifrati.',
            ),
          ],
        ),
      ),
    );
  }
}
