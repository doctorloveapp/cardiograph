import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/version.dart';
import '../../core/design_system/components.dart';
import '../../core/services/platform_services.dart';

const releasesUrl = 'https://github.com/doctorloveapp/cardiograph/releases';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  final List<int> parts;
  ReleaseVersion(this.parts);
  static ReleaseVersion? parse(String text) {
    if (!RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$').hasMatch(text)) return null;
    return ReleaseVersion(text.split('.').map(int.parse).toList());
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final c = parts[i].compareTo(other.parts[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}

String? availableRelease(Object? value, String current) {
  if (value is! Map ||
      value['draft'] != false ||
      value['prerelease'] != false) {
    return null;
  }
  final tag = value['tag_name'];
  if (tag is! String || !tag.startsWith('CardioGraphVer')) return null;
  final version = tag.substring('CardioGraphVer'.length);
  final remote = ReleaseVersion.parse(version),
      local = ReleaseVersion.parse(current);
  if (remote == null || local == null || remote.compareTo(local) <= 0) {
    return null;
  }
  final assets = value['assets'];
  if (assets is! List ||
      !assets.any(
        (a) =>
            a is Map &&
            a['name'] == 'CardioGraph.Ver$version.apk' &&
            a['state'] == 'uploaded',
      )) {
    return null;
  }
  return version;
}

Future<Object?> readLatestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    return await (() async {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/doctorloveapp/cardiograph/releases/latest',
        ),
      );
      request.followRedirects = false;
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'CardioGraph-update-check');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 512 * 1024) return null;
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    })().timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<bool> autoUpdatesEnabled() async =>
    await AndroidDocumentFileService.channel.invokeMethod<bool>(
      'autoUpdates',
    ) ??
    true;
Future<void> openReleases() =>
    AndroidDocumentFileService.channel.invokeMethod('openReleases');
Future<String?> checkForUpdate({
  required bool enabled,
  required Future<Object?> Function() load,
  String current = AppVersion.name,
}) async {
  if (!enabled) return null;
  try {
    return availableRelease(await load(), current);
  } catch (_) {
    return null;
  }
}

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool enabled = true, busy = true;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final flag = await autoUpdatesEnabled();
      if (mounted) setState(() => enabled = flag);
    } catch (_) {
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aggiornamenti')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Controllo automatico aggiornamenti'),
                value: enabled,
                onChanged: busy
                    ? null
                    : (flag) async {
                        setState(() => busy = true);
                        try {
                          await AndroidDocumentFileService.channel.invokeMethod(
                            'setAutoUpdates',
                            {'enabled': flag},
                          );
                          if (mounted) setState(() => enabled = flag);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Preferenza non salvata. Riprova.',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
              ),
              const Text(
                'Attivo di default. A ogni avvio controlla le release pubbliche su GitHub. Nessuna misurazione viene inviata; senza rete il diario resta disponibile.',
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.open_in_browser),
                title: const Text('Ultima release'),
                subtitle: const Text('Apri le release ufficiali su GitHub'),
                onTap: () async {
                  try {
                    await openReleases();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nessun browser disponibile.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
