import 'dart:io';
import '../features/settings/updates_page.dart';
import '../features/settings/privacy_page.dart';
import '../features/reminders/reminder_sync.dart';
import '../features/settings/about_page.dart';
import '../features/backup/backup_service.dart';
import '../features/backup/backup_settings.dart';
import '../core/design_system/components.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../features/reports/reports_page.dart';
import '../features/reminders/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/design_system/theme.dart';
import '../features/screens.dart';
import 'providers.dart';
import '../features/measurements/manual_editor.dart';
import '../features/measurements/diary.dart';
import '../features/measurements/measurement.dart';
import '../features/measurements/camera_page.dart';
import '../features/measurements/photo_review.dart';
import '../core/services/contracts.dart';
import '../features/analytics/analytics_page.dart';
import '../features/calendar/calendar_page.dart';

GoRouter createRouter() => GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellPage(shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (c, s) => const HomePage())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/trends', builder: (c, s) => const AnalyticsPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/calendar', builder: (c, s) => const CalendarPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/reports', builder: (c, s) => const ReportsPage()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/new-measurement',
      builder: (c, s) => const NotificationMeasurementPage(),
    ),
    GoRoute(path: '/about', builder: (c, s) => const AboutPage()),
    GoRoute(path: '/guide', builder: (c, s) => const GuidePage()),
    GoRoute(path: '/privacy', builder: (c, s) => const PrivacyPage()),
    GoRoute(path: '/updates', builder: (c, s) => const UpdatesPage()),
    GoRoute(
      path: '/settings/reminders',
      builder: (c, s) => reminderSettingsPage(),
    ),
    GoRoute(path: '/settings/backup', builder: (c, s) => backupSettingsPage()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
    GoRoute(path: '/capture', builder: (c, s) => const CameraPage()),
    GoRoute(
      path: '/review',
      builder: (c, s) => PhotoReviewPage(s.extra as CapturedImage),
    ),
    GoRoute(path: '/manual', builder: (c, s) => const ManualEditor()),
    GoRoute(
      path: '/edit',
      builder: (c, s) => ManualEditor(initial: s.extra as Measurement),
    ),
    GoRoute(path: '/diary', builder: (c, s) => const DiaryPage()),
    GoRoute(
      path: '/measurement/:id',
      builder: (c, s) => ReadingDetailPage(s.pathParameters['id']!),
    ),
  ],
  errorBuilder: (c, s) => Scaffold(
    appBar: AppBar(title: const Text('CardioGraph')),
    body: Center(
      child: TextButton(
        onPressed: () => c.go('/'),
        child: const Text('Torna alla Home'),
      ),
    ),
  ),
);
final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});

class CardioGraphApp extends ConsumerStatefulWidget {
  const CardioGraphApp({super.key});
  @override
  ConsumerState<CardioGraphApp> createState() => _CardioGraphAppState();
}

class _CardioGraphAppState extends ConsumerState<CardioGraphApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidReminderScheduler.channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTap') await _launch();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startup()));
  }

  Future<void> _startup() async {
    unawaited(_updates());
    await _launch();
    await _recoverPending();
  }

  Future<void> _updates() async {
    if (!Platform.isAndroid) return;
    try {
      final version = await checkForUpdate(
        enabled: await autoUpdatesEnabled(),
        load: readLatestRelease,
      );
      if (version == null || !mounted || !await autoUpdatesEnabled()) return;
      final context = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (context == null || !context.mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => GlassDialog(
          title: const Text('Aggiornamento disponibile'),
          content: Text(
            'È disponibile CardioGraph $version. Apri GitHub per scaricare la nuova versione.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Più tardi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Apri release'),
            ),
          ],
        ),
      );
      if (open == true) await openReleases();
    } catch (_) {
      /* Offline and platform failures never block the diary. */
    }
  }

  Future<void> _recoverPending() async {
    try {
      final service = await ref.read(backupServiceProvider.future);
      if (!mounted) return;
      // Permission dialogs can resume the app while a preference write holds
      // the fence. That is not a failed restore or pending reconciliation.
      if (service.db.maintenance) return;
      final done = await service.recover();
      await service.db.exclusive(
        () => ReminderSync(service.repository).apply(),
      );
      if (mounted) ref.read(recoveryWarningProvider.notifier).set(!done);
    } catch (_) {
      if (mounted) ref.read(recoveryWarningProvider.notifier).set(true);
    }
  }

  Future<void> _launch() async {
    try {
      final requested = await AndroidReminderScheduler.channel
          .invokeMethod<bool>('takeLaunch');
      if (requested == true && mounted) {
        final router = ref.read(routerProvider);
        if (router.routeInformationProvider.value.uri.path !=
            '/new-measurement') {
          router.push('/new-measurement');
        }
      }
    } on MissingPluginException {
      /* Desktop/widget tests have no Android platform. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  Future<void> _resume() async {
    try {
      await ref.read(reminderSchedulerProvider).reconcile();
      await _launch();
      await _recoverPending();
    } on MissingPluginException {
      /* Android only. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidReminderScheduler.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    builder: (context, child) => GlassBackdrop(child: child!),
    title: 'CardioGraph',
    debugShowCheckedModeBanner: false,
    locale: const Locale('it', 'IT'),
    supportedLocales: const [Locale('it', 'IT')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(ref.watch(opaqueProvider)),
    routerConfig: ref.watch(routerProvider),
  );
}

class NotificationMeasurementPage extends StatelessWidget {
  const NotificationMeasurementPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nuova misurazione')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => context.push('/capture'),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Scatta foto'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/manual'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Inserisci a mano'),
          ),
        ],
      ),
    ),
  );
}
