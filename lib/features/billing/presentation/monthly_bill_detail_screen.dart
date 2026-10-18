import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class MonthlyBillDetailScreen extends ConsumerWidget {
  const MonthlyBillDetailScreen({required this.cycleId, super.key});
  final String cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(appSessionProvider).state.workspace;
    if (workspace == null) {
      return const Scaffold(
        body: PropertyStatePanel(
          icon: Icons.lock_outline_rounded,
          title: 'Owner workspace unavailable',
          message: 'Return to the dashboard and try again.',
        ),
      );
    }
    final ownerId = workspace.ownerUid;
    final cycles = ref.watch(monthlyBillingCyclesProvider(ownerId));
    final controls = ref.watch(billingCycleControlsProvider(ownerId));
    final accounts = ref.watch(boarderBillAccountsProvider(ownerId));
    final payments = ref.watch(paymentRecordsProvider(ownerId));
    final sources = [cycles, controls, accounts, payments];
    final failure = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monthly bill')),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Monthly bill could not be loaded',
            message: propertyErrorMessage(failure.error!),
            actionLabel: 'Try again',
            onAction: () => _invalidate(ref, ownerId),
          ),
        ),
      );
    }
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monthly bill')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final cycle = cycles.requireValue
        .where((item) => item.billingCycleId == cycleId)
        .firstOrNull;
    final control = controls.requireValue
        .where((item) => item.billingCycleId == cycleId)
        .firstOrNull;
    if (cycle == null || control == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monthly bill')),
        body: const AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.receipt_long_outlined,
            title: 'Monthly bill not found',
            message:
                'This bill is unavailable or belongs to another workspace.',
          ),
        ),
      );
    }
    final cycleAccounts = accounts.requireValue
        .where((item) => item.billingCycleId == cycleId)
        .toList();
    final cyclePayments = payments.requireValue
        .where((item) => item.billingCycleId == cycleId)
        .toList();
    return _Details(
      ownerId: ownerId,
      cycle: cycle,
      control: control,
      accounts: cycleAccounts,
      payments: cyclePayments,
    );
  }

  void _invalidate(WidgetRef ref, String ownerId) {
    ref.invalidate(monthlyBillingCyclesProvider(ownerId));
    ref.invalidate(billingCycleControlsProvider(ownerId));
    ref.invalidate(boarderBillAccountsProvider(ownerId));
    ref.invalidate(paymentRecordsProvider(ownerId));
  }
}

class _Details extends ConsumerWidget {
  const _Details({
    required this.ownerId,
    required this.cycle,
    required this.control,
    required this.accounts,
    required this.payments,
  });
  final String ownerId;
  final MonthlyBillingCycle cycle;
  final BillingCycleControl control;
  final List<BoarderBillAccount> accounts;
  final List<PaymentRecord> payments;

  // Retained for decoding archived records; legacy bills are intentionally read-only.
  // ignore: unused_element
  Future<void> _payment(
    BuildContext context,
    WidgetRef ref,
    BoarderBillAccount account,
  ) async {
    final request = await showDialog<_PaymentRequest>(
      context: context,
      builder: (context) => _PaymentDialog(account: account),
    );
    if (request == null || !context.mounted) return;
    try {
      await ref
          .read(monthlyBillingRepositoryProvider)
          .recordPayment(
            ownerId: ownerId,
            billingCycleId: cycle.billingCycleId,
            boarderId: account.boarderId,
            amountCentavos: request.amountCentavos,
            paymentDate: request.paymentDate,
            method: request.method,
            notes: request.notes,
          );
      _invalidate(ref);
      if (context.mounted) showPropertyMessage(context, 'Payment recorded.');
    } catch (error) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.report_gmailerrorred_outlined),
        title: const Text('Void this billing cycle?'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Correction reason',
            helperText: 'The original snapshot remains in history.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(context, value);
            },
            child: const Text('Void cycle'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(monthlyBillingRepositoryProvider)
          .voidCycle(
            ownerId: ownerId,
            billingCycleId: cycle.billingCycleId,
            reason: reason,
          );
      _invalidate(ref);
      if (context.mounted) context.go('/billing/monthly');
    } catch (error) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(monthlyBillingCyclesProvider(ownerId));
    ref.invalidate(billingCycleControlsProvider(ownerId));
    ref.invalidate(boarderBillAccountsProvider(ownerId));
    ref.invalidate(paymentRecordsProvider(ownerId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final accountsByBoarder = {
      for (final item in accounts) item.boarderId: item,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly bill')),
      body: SafeArea(
        child: ListView(
          children: [
            AdaptivePageBody(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Immutable charge snapshot',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (control.state == BillingCycleState.voided)
                                Chip(
                                  avatar: const Icon(
                                    Icons.block_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Voided'),
                                )
                              else
                                PaymentStatusPill(
                                  status: control.paymentStatus,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            formatMonthlyPeriod(
                              cycle.startDate,
                              cycle.endDateExclusive,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Version ${cycle.version} - finalized ${_timestamp(cycle.finalizedAt)}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (control.state == BillingCycleState.voided) ...[
                    const SizedBox(height: 10),
                    BillingNotice(
                      isError: true,
                      message:
                          'Voided: ${control.voidReason ?? 'Documented correction'}. This version remains read-only.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          BillingValueRow(
                            label: 'Total charges',
                            value: formatPeso(control.totalBilledCentavos),
                          ),
                          BillingValueRow(
                            label: 'Payments received',
                            value: formatPeso(control.totalPaidCentavos),
                          ),
                          const Divider(height: 24),
                          BillingValueRow(
                            label: 'Remaining balance',
                            value: formatPeso(control.outstandingCentavos),
                            emphasized: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Boarder bills',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...cycle.statements.map((statement) {
                    final account = accountsByBoarder[statement.boarderId];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                Text(
                                  statement.boarderName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (account != null)
                                  PaymentStatusPill(status: account.status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            BillingValueRow(
                              label: 'Rent',
                              value: formatPeso(statement.rentCentavos),
                            ),
                            if (statement.rentAdjustmentCentavos != 0)
                              BillingValueRow(
                                label: 'Adjustments',
                                value: _signedPeso(
                                  statement.rentAdjustmentCentavos,
                                ),
                              ),
                            BillingValueRow(
                              label: 'Electricity',
                              value: formatPeso(statement.electricityCentavos),
                            ),
                            BillingValueRow(
                              label: 'Water',
                              value: formatPeso(statement.waterCentavos),
                            ),
                            const Divider(height: 20),
                            BillingValueRow(
                              label: 'Current charges',
                              value: formatPeso(
                                statement.currentChargesCentavos,
                              ),
                              emphasized: true,
                            ),
                            if (statement.previousBalanceCentavos > 0)
                              BillingValueRow(
                                label: 'Previous balance at finalization (informational)',
                                value: formatPeso(
                                  statement.previousBalanceCentavos,
                                ),
                              ),
                            if (account != null) ...[
                              BillingValueRow(
                                label: 'Paid on this bill',
                                value: formatPeso(account.totalPaidCentavos),
                              ),
                              BillingValueRow(
                                label: 'Remaining on this bill',
                                value: formatPeso(account.outstandingCentavos),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  Text(
                    'Payment history',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (payments.isEmpty)
                    const BillingNotice(
                      message: 'No payments have been recorded for this cycle.',
                    )
                  else
                    ...payments.map(
                      (payment) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(
                            '${payment.boarderName} - ${formatPeso(payment.amountCentavos)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${formatBusinessDate(payment.paymentDate)} - ${formatPaymentMethod(payment.method)}${payment.notes == null ? '' : '\n${payment.notes}'}',
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    key: const Key('generate-pdf-button'),
                    onPressed: () => context.push(
                      '/billing/monthly/${Uri.encodeComponent(cycle.billingCycleId)}/reports',
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Generate or share PDF'),
                  ),
                  const SizedBox(height: 10),
                  const BillingNotice(
                    message: 'Legacy boarder bills are read-only. Create and collect new bills from the Room bills dashboard.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRequest {
  const _PaymentRequest({
    required this.amountCentavos,
    required this.paymentDate,
    required this.method,
    required this.notes,
  });
  final int amountCentavos;
  final BusinessDate paymentDate;
  final PaymentMethod method;
  final String? notes;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.account});
  final BoarderBillAccount account;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController = TextEditingController(
    text: centavosToInput(widget.account.outstandingCentavos),
  );
  final _notesController = TextEditingController();
  late BusinessDate _date = BusinessDate.todayInManila();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PaymentRequest(
        amountCentavos: parsePesoToCentavos(_amountController.text)!,
        paymentDate: _date,
        method: _method,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Payment from ${widget.account.boarderName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BillingNotice(
                  message:
                      'Remaining balance: ${formatPeso(widget.account.outstandingCentavos)}',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('payment-amount-field'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Payment amount',
                    prefixText: 'PHP ',
                  ),
                  validator: (value) {
                    try {
                      final amount = parsePesoToCentavos(value ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Enter an amount greater than zero.';
                      }
                      if (amount > widget.account.outstandingCentavos) {
                        return 'Payment cannot exceed the remaining balance.';
                      }
                    } on FormatException catch (error) {
                      return error.message;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: PaymentMethod.values
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(formatPaymentMethod(method)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _method = value!),
                ),
                const SizedBox(height: 12),
                _PaymentDateField(
                  value: _date,
                  onChanged: (value) => setState(() => _date = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-payment-button'),
          onPressed: _submit,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _PaymentDateField extends StatelessWidget {
  const _PaymentDateField({required this.value, required this.onChanged});
  final BusinessDate value;
  final ValueChanged<BusinessDate> onChanged;

  Future<void> _pick(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      helpText: 'Payment date',
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null) onChanged(BusinessDate.fromDateTime(selected));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Payment date, ${formatBusinessDate(value)}',
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Payment date',
            prefixIcon: Icon(Icons.calendar_today_outlined),
            suffixIcon: Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(formatBusinessDate(value)),
        ),
      ),
    );
  }
}

String _signedPeso(int centavos) {
  if (centavos == 0) return formatPeso(0);
  return '${centavos > 0 ? '+' : '-'}${formatPeso(centavos.abs())}';
}

String _timestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day}/${local.year} at $hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}
