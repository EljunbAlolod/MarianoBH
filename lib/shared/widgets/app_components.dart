import 'package:flutter/material.dart';

import '../../features/property_management/presentation/widgets/property_formatters.dart';

/// A calm, content-sized introduction shared by operational screens.
class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.eyebrow,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: colors.onPrimaryContainer)),
          const SizedBox(height: 16),
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-interactive progress labels; wrapping keeps large text accessible.
class WorkflowProgress extends StatelessWidget {
  const WorkflowProgress({
    super.key,
    required this.steps,
    required this.current,
  });
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < steps.length; i++)
            Semantics(
              label:
                  'Step ${i + 1} of ${steps.length}: ${steps[i]}${i == current
                      ? ', current'
                      : i < current
                      ? ', completed'
                      : ''}',
              excludeSemantics: true,
              child: Chip(
                avatar: Icon(
                  i < current
                      ? Icons.check_rounded
                      : i == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: i <= current
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                backgroundColor: i <= current
                    ? colors.primaryContainer
                    : colors.surfaceContainerLow,
                side: BorderSide.none,
                label: Text(
                  '${i + 1}. ${steps[i]}',
                  style: TextStyle(
                    color: i <= current
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Content-sized columns: never use a fixed aspect ratio for scalable text.
class AdaptiveTiles extends StatelessWidget {
  const AdaptiveTiles({super.key, required this.children, this.minWidth = 150});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final columns = largeText
          ? 1
          : (constraints.maxWidth / (minWidth + 12)).floor().clamp(1, 3);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
              child: child,
            ),
        ],
      );
    },
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class FinancialAmount extends StatelessWidget {
  const FinancialAmount(this.centavos, {super.key});
  final int centavos;
  @override
  Widget build(BuildContext context) => Text(
    formatPeso(centavos),
    style: Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

class ActionListItem extends StatelessWidget {
  const ActionListItem({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: colors.onPrimaryContainer),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const ExcludeSemantics(
          child: Icon(Icons.chevron_right, size: 20),
        ),
      ),
    );
  }
}

class RecordSearchField extends StatelessWidget {
  const RecordSearchField({
    super.key,
    required this.label,
    required this.onChanged,
  });
  final String label;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.search, size: 24),
    ),
  );
}
