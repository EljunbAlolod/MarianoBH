import 'package:flutter/material.dart';

import '../../../shared/widgets/brand_mark.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 960 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            final introduction = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineMedium),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (wide) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Rooms. Boarders. Bills.',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your boarding-house records, together in one place.',
                  ),
                ],
              ],
            );
            final form = Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(wide ? 32 : 20),
                child: child,
              ),
            );
            return Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(constraints.maxWidth < 400 ? 16 : 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1040 : 480),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: introduction),
                            const SizedBox(width: 64),
                            Expanded(child: form),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            introduction,
                            const SizedBox(height: 24),
                            form,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
