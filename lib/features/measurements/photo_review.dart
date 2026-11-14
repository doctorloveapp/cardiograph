import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/contracts.dart';
import '../../core/services/photo_services.dart';
import '../../core/vision/seven_segment.dart';
import 'manual_editor.dart';

class PhotoReviewPage extends ConsumerStatefulWidget {
  final CapturedImage photo;
  const PhotoReviewPage(this.photo, {super.key});
  @override
  ConsumerState<PhotoReviewPage> createState() => _PhotoReviewPageState();
}

class _PhotoReviewPageState extends ConsumerState<PhotoReviewPage> {
  OcrCandidate? _candidate;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize([DisplayCrop? crop]) async {
    setState(() => _busy = true);
    try {
      final candidate = await ref
          .read(ocrServiceProvider)
          .recognize(widget.photo, crop: crop);
      if (mounted) {
        setState(() {
          _candidate = candidate;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Foto non leggibile. Rifila il display, ripeti la foto oppure completa i tre campi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop() async {
    final choice = await Navigator.of(context).push<DisplayCrop>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          widget.photo,
          initial:
              _candidate?.display?.crop ??
              widget.photo.guideCrop ??
              DisplayCrop.full,
        ),
      ),
    );
    if (choice != null && mounted) await _recognize(choice);
  }

  @override
  Widget build(BuildContext context) => ManualEditor(
    photo: widget.photo,
    candidate: _candidate,
    recognizing: _busy,
    photoHeader: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_candidate?.display != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              _candidate!.display!.preview,
              height: 280,
              fit: BoxFit.contain,
              semanticLabel: 'Display fotografato da verificare',
            ),
          )
        else
          Image.file(
            File(widget.photo.path),
            height: 220,
            fit: BoxFit.contain,
            semanticLabel: 'Fotografia da verificare',
            errorBuilder: (context, error, stack) =>
                const Text('Anteprima non disponibile. Ripeti la foto.'),
          ),
        if (_busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Riconoscimento del display in corso',
          ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (!_busy && _candidate?.display?.issue != null)
          Text(_candidate!.display!.issue!),
        OutlinedButton.icon(
          onPressed: _busy ? null : _crop,
          icon: const Icon(Icons.crop),
          label: const Text('Rifila e riconosci di nuovo'),
        ),
        const Text(
          'Il nuovo riconoscimento sostituisce i tre campi. Nessun salvataggio automatico.',
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

class CropPage extends StatefulWidget {
  final CapturedImage photo;
  final DisplayCrop initial;
  const CropPage(this.photo, {super.key, required this.initial});
  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late Rect _rect;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _rect = Rect.fromLTRB(c.left, c.top, c.right, c.bottom);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rifila il display')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Trascina i quattro angoli. Includi soltanto il display e i tre numeri, senza tagliare le cifre.',
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: widget.photo.width / widget.photo.height,
          child: LayoutBuilder(
            builder: (c, box) => Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(widget.photo.path), fit: BoxFit.fill),
                Positioned(
                  left: _rect.left * box.maxWidth,
                  top: _rect.top * box.maxHeight,
                  width: _rect.width * box.maxWidth,
                  height: _rect.height * box.maxHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left:
                        ((i % 2 == 0 ? _rect.left : _rect.right) *
                                    box.maxWidth -
                                24)
                            .clamp(0, box.maxWidth - 48),
                    top:
                        ((i < 2 ? _rect.top : _rect.bottom) * box.maxHeight -
                                24)
                            .clamp(0, box.maxHeight - 48),
                    child: Semantics(
                      label: 'Angolo ritaglio ${i + 1}',
                      child: GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          final dx = d.delta.dx / box.maxWidth,
                              dy = d.delta.dy / box.maxHeight;
                          _rect = Rect.fromLTRB(
                            i % 2 == 0
                                ? (_rect.left + dx).clamp(0, _rect.right - .10)
                                : _rect.left,
                            i < 2
                                ? (_rect.top + dy).clamp(0, _rect.bottom - .10)
                                : _rect.top,
                            i % 2 == 1
                                ? (_rect.right + dx).clamp(_rect.left + .10, 1)
                                : _rect.right,
                            i >= 2
                                ? (_rect.bottom + dy).clamp(_rect.top + .10, 1)
                                : _rect.bottom,
                          );
                        }),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.open_with,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Sliders also make precision adjustment accessible without drag gestures.
        for (var i = 0; i < 4; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(['Sinistra', 'Alto', 'Destra', 'Basso'][i]),
              Slider(
                label: ['Sinistra', 'Alto', 'Destra', 'Basso'][i],
                value: [_rect.left, _rect.top, _rect.right, _rect.bottom][i],
                min: i == 2
                    ? _rect.left + .10
                    : i == 3
                    ? _rect.top + .10
                    : 0,
                max: i == 0
                    ? _rect.right - .10
                    : i == 1
                    ? _rect.bottom - .10
                    : 1,
                onChanged: (v) => setState(
                  () => _rect = Rect.fromLTRB(
                    i == 0 ? v : _rect.left,
                    i == 1 ? v : _rect.top,
                    i == 2 ? v : _rect.right,
                    i == 3 ? v : _rect.bottom,
                  ),
                ),
              ),
            ],
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            DisplayCrop(_rect.left, _rect.top, _rect.right, _rect.bottom),
          ),
          child: const Text('Riconosci ritaglio'),
        ),
      ],
    ),
  );
}
