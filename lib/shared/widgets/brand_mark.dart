import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 44 : 56,
          height: compact ? 44 : 56,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(compact ? 13 : 17),
          ),
          child: Icon(
            Icons.apartment_rounded,
            color: colors.onPrimaryContainer,
            size: compact ? 26 : 32,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            'Boarding House\nManager',
            softWrap: true,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.05),
          ),
        ),
      ],
    );
  }
}
