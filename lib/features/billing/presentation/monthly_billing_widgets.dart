import 'package:flutter/material.dart';

import '../../property_management/presentation/widgets/property_formatters.dart';
import '../domain/monthly_billing_models.dart';
import 'monthly_billing_formatters.dart';

class BillingValueRow extends StatelessWidget {
  const BillingValueRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(16) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label),
                const SizedBox(height: 3),
                Align(alignment: Alignment.centerRight, child: valueWidget),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 16),
              Flexible(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}

class BillingNotice extends StatelessWidget {
  const BillingNotice({required this.message, this.isError = false, super.key});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.tertiaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

class PaymentStatusPill extends StatelessWidget {
  const PaymentStatusPill({required this.status, super.key});
  final BillPaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (status) {
      BillPaymentStatus.paid => (
        Icons.check_circle_outline_rounded,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      BillPaymentStatus.partiallyPaid => (
        Icons.timelapse_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      BillPaymentStatus.unpaid => (
        Icons.pending_actions_outlined,
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };
    return Semantics(
      label: 'Payment status: ${formatPaymentStatus(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                formatPaymentStatus(status),
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BillingMetricCard extends StatelessWidget {
  const BillingMetricCard({
    required this.label,
    required this.centavos,
    required this.icon,
    super.key,
  });

  final String label;
  final int centavos;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: colors.primary)),
          const SizedBox(height: 10),
          Text(
            formatPeso(centavos),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
