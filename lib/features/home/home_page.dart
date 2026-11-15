import '../../core/text/italian.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/time/measurement_time.dart';
import '../../core/design_system/theme.dart';
import '../measurements/diary.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).now();
    return ArchiveState(
      builder: (rows) {
        final today = rows.where((m) => m.localDate == dateKey(now)).toList();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/logo.png',
                  width: 44,
                  height: 44,
                  semanticLabel: 'Logo CardioGraph',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Diario pressorio',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Registro misurazioni · ${now.day}/${now.month}/${now.year}'),
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Semantics(
                      label: 'Nuova misurazione',
                      button: true,
                      excludeSemantics: true,
                      onTap: () => context.push('/capture'),
                      child: InkWell(
                        onTap: () => context.push('/capture'),
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Brand.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .75),
                                    width: 1.5,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xffc7354a),
                                      Brand.red,
                                      Color(0xff921c30),
                                    ],
                                    stops: [0, .45, 1],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Brand.red.withValues(alpha: .22),
                                      blurRadius: 20,
                                      offset: const Offset(4, 9),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Nuova misurazione',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      iconSize: 22,
                    ),
                    onPressed: () => context.push('/diary'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Apri diario'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oggi · ${countNoun(today.length, 'misurazione', 'misurazioni')}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Row(
                key: const ValueKey('home-band-row'),
                children: [
                  for (final band in TimeBand.values)
                    Expanded(
                      child: Semantics(
                        label:
                            '${band.label}: ${countNoun(today.where((m) => m.band.index == band.index).length, 'misurazione', 'misurazioni')}',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            children: [
                              Icon(band.icon, size: 20, color: Brand.ink),
                              const SizedBox(height: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  band.label,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(height: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${today.where((m) => m.band.index == band.index).length}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (rows.isEmpty)
              const EmptyState(
                title: 'Nessuna misurazione',
                message:
                    'Nessuna rilevazione presente. Registra una misurazione per consultare il riepilogo.',
                icon: Icons.favorite_outline,
              )
            else ...[
              Text(
                'Ultima lettura',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ReadingCard(
                rows.first,
                onOpen: () => context.push('/measurement/${rows.first.id}'),
              ),
            ],
          ],
        );
      },
    );
  }
}
