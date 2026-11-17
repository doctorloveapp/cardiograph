import 'package:flutter/material.dart';
import 'theme.dart';

class RangeBadge extends StatelessWidget {
  final String label;
  final int hex;
  const RangeBadge(this.label, this.hex, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Color(hex),
            shape: BoxShape.circle,
            border: Border.all(color: Brand.navy.withValues(alpha: .5)),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: Brand.navy,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
