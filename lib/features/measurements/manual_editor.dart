import '../../core/design_system/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/time/measurement_time.dart';
import '../../core/validation/measurement_validation.dart';
import '../../data/providers.dart';
import 'measurement.dart';
import '../../core/services/contracts.dart';

class ManualEditor extends ConsumerStatefulWidget {
  final Measurement? initial;
  final CapturedImage? photo;
  final OcrCandidate? candidate;
  final Widget? photoHeader;
  final bool recognizing;
  const ManualEditor({
    super.key,
    this.initial,
    this.photo,
    this.candidate,
    this.photoHeader,
    this.recognizing = false,
  });
  @override
  ConsumerState<ManualEditor> createState() => _ManualEditorState();
}

class _ManualEditorState extends ConsumerState<ManualEditor> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _numbers;
  late final TextEditingController _note;
  late final String _id;
  late final DateTime _created;
  late DateTime _wall;
  late final Future<String> _zone;
  bool _dirty = false, _saving = false, _allowPop = false, _timeChanged = false;
  bool _timeConfirmed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    final photo = widget.photo;
    final now = photo == null
        ? ref.read(clockProvider).now()
        : photo.capturedAt.toUtc().add(Duration(minutes: photo.offsetMinutes));
    _id = m?.id ?? newMeasurementId();
    _created = m?.createdAtUtc ?? ref.read(clockProvider).now().toUtc();
    _wall =
        m?.wall ??
        DateTime.utc(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
          now.second,
        );
    _numbers = [
      m?.systolic ?? widget.candidate?.systolic,
      m?.diastolic ?? widget.candidate?.diastolic,
      m?.pulse ?? widget.candidate?.pulse,
    ].map((v) => TextEditingController(text: v?.toString() ?? '')).toList();
    _note = TextEditingController(text: m?.note ?? '');
    _zone = m != null
        ? Future.value(m.zone)
        : photo != null
        ? Future.value(photo.zone)
        : ref.read(zoneLookupProvider)();
    _dirty = photo != null;
  }

  @override
  void didUpdateWidget(covariant ManualEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.candidate != oldWidget.candidate && widget.candidate != null) {
      final c = widget.candidate!;
      final values = [c.systolic, c.diastolic, c.pulse];
      for (var i = 0; i < 3; i++) {
        _numbers[i].text = values[i]?.toString() ?? '';
      }
    }
  }

  @override
  void dispose() {
    for (final c in _numbers) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String yes = 'Conferma',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => GlassDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Rivedi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(yes),
            ),
          ],
        ),
      ) ??
      false;
  void _close([bool? retake]) {
    setState(() {
      _allowPop = true;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop(retake);
    });
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (!_dirty ||
        await _confirm(
          'Uscire senza salvare?',
          'Le modifiche inserite in questa schermata verranno scartate.',
          yes: 'Scarta modifiche',
        )) {
      if (mounted) _close();
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _wall,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null && mounted) {
      setState(() {
        _wall = DateTime.utc(
          d.year,
          d.month,
          d.day,
          _wall.hour,
          _wall.minute,
          _wall.second,
        );
        _dirty = true;
        _timeChanged = true;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && mounted) {
      setState(() {
        _wall = DateTime.utc(
          _wall.year,
          _wall.month,
          _wall.day,
          t.hour,
          t.minute,
        );
        _dirty = true;
        _timeChanged = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || widget.recognizing || !_form.currentState!.validate()) {
      return;
    }
    if (widget.photo != null && !widget.photo!.precise && !_timeConfirmed) {
      setState(
        () => _error =
            'Verifica e conferma la data e l’ora: il sensore non fornisce un riferimento UTC affidabile.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final zone = await _zone;
      if (!mounted) return;
      final old = widget.initial;
      late DateTime utc;
      late int offset;
      if (widget.photo != null && !_timeChanged) {
        utc = widget.photo!.capturedAt.toUtc();
        offset = widget.photo!.offsetMinutes;
      } else if (old != null && !_timeChanged) {
        utc = old.measuredAtUtc;
        offset = old.offsetMinutes;
      } else {
        final candidates = resolveWall(_wall, zone);
        if (candidates.isEmpty) {
          setState(
            () => _error =
                'Questo orario non esiste per il cambio dell’ora. Scegli un altro orario.',
          );
          return;
        }
        var choice = candidates.first;
        if (candidates.length > 1) {
          final index = await showDialog<int>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const Text('Orario ripetuto: scegli l’offset'),
              children: [
                for (var i = 0; i < candidates.length; i++)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, i),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${timeKey(_wall)} · UTC${candidates[i].timeZoneOffset.isNegative ? '-' : '+'}${(candidates[i].timeZoneOffset.inMinutes.abs() ~/ 60).toString().padLeft(2, '0')}:${(candidates[i].timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
              ],
            ),
          );
          if (index == null) return;
          choice = candidates[index];
        }
        utc = choice.toUtc();
        offset = choice.timeZoneOffset.inMinutes;
      }
      if (!mounted) return;
      final values = _numbers.map((c) => int.parse(c.text)).toList();
      if (values[0] <= values[1] &&
          !await _confirm(
            'Verifica massima e minima',
            'La massima è minore o uguale alla minima. Confermi i valori senza scambiarli?',
          )) {
        return;
      }
      if (!mounted) return;
      if (utc.isAfter(ref.read(clockProvider).now().toUtc()) &&
          !await _confirm(
            'Data futura',
            'La lettura risulta nel futuro. Controlla data e orologio del telefono: vuoi conservarla così?',
          )) {
        return;
      }
      final record = Measurement(
        id: _id,
        systolic: values[0],
        diastolic: values[1],
        pulse: values[2],
        measuredAtUtc: utc,
        zone: zone,
        offsetMinutes: offset,
        localDate: dateKey(_wall),
        localTime: timeKey(_wall),
        source: old?.source ?? (widget.photo == null ? 'manual' : 'camera'),
        note: _note.text,
        createdAtUtc: _created,
        updatedAtUtc: ref.read(clockProvider).now().toUtc(),
        revision: old == null ? 0 : old.revision + 1,
        originalCapturedAtUtc:
            old?.originalCapturedAtUtc ??
            (widget.photo?.precise == true
                ? widget.photo!.capturedAt.toUtc()
                : null),
      );
      final repo = await ref.read(measurementRepositoryProvider.future);
      if (!mounted) return;
      if (await repo.possibleDuplicate(record)) {
        if (!mounted ||
            !await _confirm(
              'Possibile doppione',
              'Una lettura con gli stessi valori è già presente entro due minuti. Vuoi conservarle entrambe?',
              yes: 'Salva comunque',
            )) {
          return;
        }
      }
      await repo.save(record, editing: old != null);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Misurazione salvata')));
      _close();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : 'Salvataggio non riuscito. I valori restano qui: controlla lo spazio disponibile e riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: (!_dirty || _allowPop) && !_saving,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _leave),
        title: Text(
          widget.photo != null
              ? 'Rivedi foto'
              : widget.initial == null
              ? 'Inserisci a mano'
              : 'Modifica lettura',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (widget.photoHeader != null) widget.photoHeader!,
            if (widget.photo != null) ...[
              Text(
                widget.photo!.precise
                    ? 'Ora dello scatto · sensore REALTIME'
                    : 'Ora indicativa · sensore UNKNOWN',
              ),
              Text('Verifica i tre valori prima di confermare il salvataggio.'),
              if (!widget.photo!.precise)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ho verificato data e ora della misurazione',
                  ),
                  value: _timeConfirmed,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _timeConfirmed = v ?? false),
                ),
            ],
            Text(
              widget.photo == null
                  ? 'Dati della misurazione'
                  : 'Verifica della misurazione',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  key: ValueKey('reading-$i'),
                  controller: _numbers[i],
                  enabled: !_saving && !widget.recognizing,
                  keyboardType: TextInputType.number,
                  textInputAction: i == 2
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onFieldSubmitted: (_) {
                    if (i < 2) {
                      FocusScope.of(context).nextFocus();
                    } else {
                      FocusScope.of(context).unfocus();
                    }
                  },
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(3)],
                  validator: numberError,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(
                    helperText:
                        widget.photo != null &&
                            _numbers[i].text.isEmpty &&
                            [
                                  widget.candidate?.systolic,
                                  widget.candidate?.diastolic,
                                  widget.candidate?.pulse,
                                ][i] ==
                                null
                        ? 'Da completare o verificare'
                        : null,
                    labelText: ['Massima', 'Minima', 'Pulsazioni'][i],
                    suffixText: i == 2 ? 'bpm' : 'mmHg',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    '${_wall.day.toString().padLeft(2, '0')}/${_wall.month.toString().padLeft(2, '0')}/${_wall.year}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(timeKey(_wall)),
                ),
              ],
            ),
            FutureBuilder<String>(
              future: _zone,
              builder: (c, s) =>
                  Text('Fuso orario: ${s.data ?? 'in caricamento'}'),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              initiallyExpanded: _note.text.isNotEmpty,
              title: const Text('Nota facoltativa'),
              children: [
                TextFormField(
                  key: const ValueKey('note'),
                  controller: _note,
                  enabled: !_saving && !widget.recognizing,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nota',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v ?? '').runes.length > 500
                      ? 'Massimo 500 caratteri'
                      : null,
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ],
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving || widget.recognizing ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _saving
                    ? 'Salvataggio…'
                    : widget.photo == null
                    ? 'Salva misurazione'
                    : 'Conferma e salva',
              ),
            ),
            if (widget.photo != null)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        if (await _confirm(
                              'Ripetere la foto?',
                              'La foto e le modifiche di questa revisione verranno scartate.',
                              yes: 'Ripeti foto',
                            ) &&
                            mounted) {
                          _close(true);
                        }
                      },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Ripeti foto'),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
