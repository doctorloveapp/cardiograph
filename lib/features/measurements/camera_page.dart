import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/contracts.dart';
import '../../core/services/photo_services.dart';
import '../../core/vision/camera_guide.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});
  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage>
    with WidgetsBindingObserver {
  late final NativeCaptureService _service;
  StreamSubscription<String>? _subscription;
  String? _permission, _error;
  bool _ready = false,
      _busy = false,
      _torch = false,
      _hasTorch = false,
      _reviewing = false;
  int _previewKey = 0;
  CapturedImage? _owned;
  late final Future<TemporaryPhotoStore> _store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _service = ref.read(captureServiceProvider);
    _store = ref.read(photoStoreProvider.future);
    _subscription = _service.errors.listen((e) {
      if (mounted && !_reviewing) {
        setState(() {
          _error = e;
          _ready = false;
        });
      }
    });
    _checkPermission(true);
  }

  Future<void> _checkPermission(bool request) async {
    try {
      final state = await _service.permission(request: request);
      if (mounted) {
        setState(() {
          _permission = state;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Impossibile aprire la fotocamera. Puoi inserire la lettura a mano.',
        );
      }
    }
  }

  Future<void> _start() async {
    try {
      final torch = await _service.start();
      if (mounted && !_reviewing) {
        setState(() {
          _ready = true;
          _hasTorch = torch;
          _torch = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
          _error =
              'Fotocamera occupata o non disponibile. Chiudi le altre app e riprova.';
        });
      }
    }
  }

  Future<void> _clean(CapturedImage image) async {
    final store = await _store;
    await store.delete(image.path);
    if (_owned == image) _owned = null;
  }

  Future<void> _shoot() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final image = await _service.capture();
      _owned = image;
      if (!mounted) {
        await _clean(image);
        return;
      }
      _reviewing = true;
      await _service.close();
      if (!mounted) {
        await _clean(image);
        return;
      }
      bool? retake;
      try {
        retake = await context.push<bool>('/review', extra: image);
      } finally {
        await _clean(image);
      }
      if (!mounted) return;
      _reviewing = false;
      if (retake == true) {
        setState(() {
          _previewKey++;
          _ready = false;
          _torch = false;
        });
      } else {
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Scatto o pulizia della cache non riusciti. Riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_service.close());
      if (mounted) {
        setState(() {
          _ready = false;
          _torch = false;
        });
      }
    } else if (state == AppLifecycleState.resumed && !_reviewing) {
      _resume();
    }
  }

  Future<void> _resume() async {
    await _checkPermission(false);
    if (mounted && _permission == 'granted') setState(() => _previewKey++);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(SystemChrome.setPreferredOrientations(const []));
    _subscription?.cancel();
    unawaited(_service.close());
    // The provider is read before dispose so cleanup never depends on an invalid Ref.
    final owned = _owned;
    if (owned != null) {
      unawaited(_store.then((store) => store.delete(owned.path)));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy || _reviewing,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Scatta foto'),
        leading: BackButton(onPressed: _busy ? null : () => context.pop()),
      ),
      body: _permission != 'granted'
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Inquadra i tre valori',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text(
                  _error ??
                      (_permission == 'permanent'
                          ? 'Abilita la fotocamera nelle impostazioni del telefono.'
                          : 'Il permesso fotocamera serve soltanto per fotografare il display.'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _permission == 'permanent'
                      ? _service.settings()
                      : _checkPermission(true),
                  child: Text(
                    _permission == 'permanent'
                        ? 'Apri impostazioni'
                        : 'Consenti fotocamera',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.pushReplacement('/manual'),
                  child: const Text('Inserisci a mano'),
                ),
              ],
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Inquadra i tre valori',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Solo il display nel riquadro. Tocca per mettere a fuoco; evita i riflessi.',
                  ),
                ),
                Expanded(
                  child: _permission == 'granted'
                      ? LayoutBuilder(
                          builder: (context, _) => Stack(
                            fit: StackFit.expand,
                            children: [
                              AndroidView(
                                key: ValueKey(_previewKey),
                                viewType: 'dev.danking.cardiograph/preview',
                                onPlatformViewCreated: (_) => _start(),
                              ),
                              IgnorePointer(
                                child: Center(
                                  child: FractionallySizedBox(
                                    widthFactor: CameraGuide.fraction,
                                    heightFactor: CameraGuide.fraction,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        children: [
                                          for (var i = 0; i < 3; i++)
                                            Expanded(
                                              child: Container(
                                                alignment: Alignment.topLeft,
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: i < 2
                                                      ? const Border(
                                                          bottom: BorderSide(
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                                child: Text(
                                                  [
                                                    'Massima',
                                                    'Minima',
                                                    'Pulsazioni',
                                                  ][i],
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    backgroundColor:
                                                        Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_error != null)
                                ColoredBox(
                                  color: Colors.black87,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _error!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          FilledButton(
                                            onPressed: _start,
                                            child: const Text('Riprova'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error ??
                                      (_permission == 'permanent'
                                          ? 'Abilita la fotocamera nelle impostazioni del telefono.'
                                          : 'Il permesso fotocamera serve soltanto per fotografare il display.'),
                                ),
                                if (_permission != null)
                                  FilledButton(
                                    onPressed: () => _permission == 'permanent'
                                        ? _service.settings()
                                        : _checkPermission(true),
                                    child: Text(
                                      _permission == 'permanent'
                                          ? 'Apri impostazioni'
                                          : 'Consenti fotocamera',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        IconButton(
                          tooltip: _torch ? 'Spegni torcia' : 'Accendi torcia',
                          onPressed: !_ready || !_hasTorch || _busy
                              ? null
                              : () async {
                                  final value = !_torch;
                                  try {
                                    if (await _service.torch(value) &&
                                        mounted) {
                                      setState(() => _torch = value);
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () =>
                                            _error = 'Torcia non disponibile.',
                                      );
                                    }
                                  }
                                },
                          icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                        ),
                        FilledButton.icon(
                          onPressed: _ready && !_busy ? _shoot : null,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_busy ? 'Scatto in corso…' : 'Scatta'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.pushReplacement('/manual'),
                          child: const Text('Inserisci a mano'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}
