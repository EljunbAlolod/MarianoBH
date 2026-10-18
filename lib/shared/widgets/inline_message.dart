import 'package:flutter/material.dart';

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    required this.message,
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.isError = true,
  });

  final String message;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
