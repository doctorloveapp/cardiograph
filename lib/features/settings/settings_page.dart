import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_system/components.dart';
import '../backup/backup_settings.dart';
import '../reminders/reminders.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Impostazioni')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final item in [
          ('Promemoria', Icons.notifications_outlined, '/settings/reminders'),
          ('Backup e dati', Icons.backup_outlined, '/settings/backup'),
          ('Info', Icons.info_outline, '/about'),
        ]) ...[
          GlassCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 14,
              leading: Icon(item.$2, size: 30),
              title: Text(
                item.$1,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(item.$3),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    ),
  );
}

class SettingsSectionPage extends StatelessWidget {
  final String title;
  final Widget child;
  const SettingsSectionPage({
    super.key,
    required this.title,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.all(24), children: [child]),
  );
}

Widget reminderSettingsPage() =>
    const SettingsSectionPage(title: 'Promemoria', child: ReminderSettings());
Widget backupSettingsPage() =>
    const SettingsSectionPage(title: 'Backup e dati', child: BackupSettings());
