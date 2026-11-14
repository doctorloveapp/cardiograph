import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/design_system/theme.dart';

class ShellPage extends StatelessWidget {
  final StatefulNavigationShell shell;
  const ShellPage(this.shell, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('CardioGraph'),
      actions: [
        IconButton(
          tooltip: 'Impostazioni',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.canvas, Brand.soft, Brand.canvas],
        ),
      ),
      child: shell,
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(icon: Icon(Icons.show_chart), label: 'Andamento'),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'Calendario',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          label: 'Report',
        ),
      ],
    ),
  );
}
