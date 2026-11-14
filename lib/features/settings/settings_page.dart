import '../reminders/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => context.pop()),
      title: const Text('Impostazioni'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Leggibilità',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Riduci trasparenze'),
                subtitle: const Text(
                  'Superfici opache per una lettura più confortevole.',
                ),
                value: ref.watch(opaqueProvider),
                onChanged: ref.read(opaqueProvider.notifier).set,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const ReminderSettings(),
        const SizedBox(height: 24),
        const Text(
          'CardioGraph · 0.1.0-dev\nSviluppatore: Dan King\nUn diario personale, senza account.',
        ),
      ],
    ),
  );
}
