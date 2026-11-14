import 'package:flutter/material.dart';
import 'components.dart';

class FeaturePage extends StatelessWidget {
  final String title, message;
  final IconData icon;
  const FeaturePage({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 24),
      EmptyState(
        title: 'Il tuo diario inizia qui',
        message: message,
        icon: icon,
      ),
    ],
  );
}
