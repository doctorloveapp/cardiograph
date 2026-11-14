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
            GoRoute(
              path: '/reports',
              builder: (c, s) => const FeaturePage(
                title: 'Report',
                message:
                    'Dopo aver registrato le letture potrai preparare il tuo riepilogo PDF.',
                icon: Icons.description_outlined,
              ),
            ),
          ],
        ),
      ],
    ),
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

class CardioGraphApp extends ConsumerWidget {
  const CardioGraphApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'CardioGraph',
    debugShowCheckedModeBanner: false,
    locale: const Locale('it', 'IT'),
    supportedLocales: const [Locale('it', 'IT')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(ref.watch(opaqueProvider)),
    routerConfig: ref.watch(routerProvider),
  );
}
