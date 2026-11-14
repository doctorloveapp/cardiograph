import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_system/components.dart';

void showMeasurementChoice(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nuova misurazione',
          style: Theme.of(sheet).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text('Scegli come aggiungere la lettura.'),
        const SizedBox(height: 24),
        PrimaryAction(
          label: 'Scatta foto',
          icon: Icons.photo_camera_outlined,
          onPressed: () {
            Navigator.pop(sheet);
            context.push('/capture');
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
          onPressed: () {
            Navigator.pop(sheet);
            context.push('/manual');
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Inserisci a mano'),
        ),
      ],
    ),
  ),
);
