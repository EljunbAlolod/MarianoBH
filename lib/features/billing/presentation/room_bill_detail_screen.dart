import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../reports/application/room_billing_pdf_generator.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_models.dart';
import '../domain/room_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class RoomBillDetailScreen extends ConsumerWidget {
  const RoomBillDetailScreen({required this.cycleId, super.key});

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
    final cycles = ref.watch(roomBillingCyclesProvider(ownerId));
    final controls = ref.watch(roomBillingControlsProvider(ownerId));
    final accounts = ref.watch(roomBillAccountsProvider(ownerId));
    final payments = ref.watch(roomPaymentRecordsProvider(ownerId));
    final values = [cycles, controls, accounts, payments];
    final failure = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room bills')),
        body: SafeArea(
          child: AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.cloud_off_outlined,
              title: 'Room bill could not be loaded',
              message: propertyErrorMessage(failure.error!),
            ),
          ),
        ),
      );
    }
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room bills')),
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
        appBar: AppBar(title: const Text('Room bills')),
        body: const SafeArea(
          child: AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.search_off_rounded,
              title: 'Room bill not found',
              message:
                  'This billing month may have been removed or is unavailable.',
            ),
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
    return _Detail(
      ownerId: ownerId,
      houseName: workspace.houseName,
      cycle: cycle,
      control: control,
      accounts: cycleAccounts,
      payments: cyclePayments,
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({
    required this.ownerId,
    required this.houseName,
    required this.cycle,
    required this.control,
    required this.accounts,
    required this.payments,
  });

  final String ownerId;
  final String houseName;
  final RoomBillingCycle cycle;
  final BillingCycleControl control;
  final List<RoomBillAccount> accounts;
  final List<RoomPaymentRecord> payments;

  Future<void> _generatePdf(BuildContext context) async {
    const generator = RoomBillingPdfGenerator();
    try {
      await Printing.layoutPdf(
        name: generator.fileName(houseName, cycle),
        onLayout: (_) => generator.build(
          houseName: houseName,
          cycle: cycle,
          control: control,
          accounts: accounts,
          payments: payments,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          'The PDF could not be opened. Please try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    RoomBillAccount account,
  ) async {
    final request = await showDialog<_PaymentRequest>(
      context: context,
      builder: (context) => _RoomPaymentDialog(account: account),
    );
    if (request == null || !context.mounted) return;
    try {
      await ref
          .read(monthlyBillingRepositoryProvider)
          .recordRoomPayment(
            ownerId: ownerId,
            billingCycleId: cycle.billingCycleId,
            roomId: account.roomId,
            amountCentavos: request.amountCentavos,
            paymentDate: request.paymentDate,
            method: request.method,
            notes: request.notes,
          );
      if (context.mounted) {
        showPropertyMessage(context, 'Room payment recorded.');
      }
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

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Void this room billing month?'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            helperText: 'Required. Existing room bills remain in history.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(dialogContext, value);
            },
            child: const Text('Void bills'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(monthlyBillingRepositoryProvider)
          .voidRoomCycle(
            ownerId: ownerId,
            billingCycleId: cycle.billingCycleId,
            reason: reason,
          );
      if (context.mounted) showPropertyMessage(context, 'Room bills voided.');
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsByRoom = {for (final item in accounts) item.roomId: item};
    final paymentsByRoom = <String, List<RoomPaymentRecord>>{};
    for (final payment in payments) {
      paymentsByRoom.putIfAbsent(payment.roomId, () => []).add(payment);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Room billing month')),
      body: SafeArea(
        child: ListView(
          children: [
            AdaptivePageBody(
              maxWidth: 900,
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
                        formatMonthlyPeriod(
                          cycle.startDate,
                          cycle.endDateExclusive,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      control.state == BillingCycleState.voided
                          ? const Chip(label: Text('Voided'))
                          : PaymentStatusPill(status: control.paymentStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    key: const Key('generate-room-bills-pdf'),
                    onPressed: () => _generatePdf(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Generate room bills PDF'),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          BillingValueRow(
                            label: 'Billed',
                            value: formatPeso(control.totalBilledCentavos),
                          ),
                          BillingValueRow(
                            label: 'Paid',
                            value: formatPeso(control.totalPaidCentavos),
                          ),
                          BillingValueRow(
                            label: 'Outstanding',
                            value: formatPeso(control.outstandingCentavos),
                            emphasized: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Room bills',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...cycle.statements.map((statement) {
                    final account = accountsByRoom[statement.roomId];
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
                                  statement.roomName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (account != null)
                                  PaymentStatusPill(status: account.status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_ranges(statement.occupiedRanges)} · ${statement.occupiedDays} occupied ${statement.occupiedDays == 1 ? 'day' : 'days'}',
                            ),
                            const SizedBox(height: 10),
                            if (statement.rentCentavos > 0)
                              BillingValueRow(
                                label: 'Rent (legacy bill)',
                                value: formatPeso(statement.rentCentavos),
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
                              label: 'Bill total',
                              value: formatPeso(
                                statement.currentChargesCentavos,
                              ),
                              emphasized: true,
                            ),
                            if (account != null) ...[
                              BillingValueRow(
                                label: 'Paid on this bill',
                                value: formatPeso(account.totalPaidCentavos),
                              ),
                              BillingValueRow(
                                label: 'Remaining',
                                value: formatPeso(account.outstandingCentavos),
                              ),
                              if (control.state == BillingCycleState.active &&
                                  account.outstandingCentavos > 0) ...[
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  key: Key(
                                    'record-room-payment-${account.roomId}',
                                  ),
                                  onPressed: () =>
                                      _recordPayment(context, ref, account),
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Record room payment'),
                                ),
                              ],
                            ],
                            if ((paymentsByRoom[statement.roomId] ?? [])
                                .isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Payment history',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              for (final payment
                                  in paymentsByRoom[statement.roomId]!)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.payments_outlined),
                                  title: Text(
                                    formatPeso(payment.amountCentavos),
                                  ),
                                  subtitle: Text(
                                    '${formatBusinessDate(payment.paymentDate)} · ${formatPaymentMethod(payment.method)}${payment.notes == null ? '' : '\n${payment.notes}'}',
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  if (control.state == BillingCycleState.active &&
                      control.totalPaidCentavos == 0) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _void(context, ref),
                      icon: Icon(
                        Icons.block_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      label: Text(
                        'Void for correction',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
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

class _RoomPaymentDialog extends StatefulWidget {
  const _RoomPaymentDialog({required this.account});

  final RoomBillAccount account;

  @override
  State<_RoomPaymentDialog> createState() => _RoomPaymentDialogState();
}

class _RoomPaymentDialogState extends State<_RoomPaymentDialog> {
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.value,
      firstDate: DateTime.utc(2000),
      lastDate: BusinessDate.todayInManila().value,
      helpText: 'Payment date',
    );
    if (picked != null) {
      setState(() => _date = BusinessDate.fromDateTime(picked));
    }
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
      title: Text('Payment for ${widget.account.roomName}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('room-payment-amount-field'),
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Payment amount',
                  prefixText: '₱ ',
                  helperText:
                      '${formatPeso(widget.account.outstandingCentavos)} remaining',
                ),
                validator: (value) {
                  final amount = parsePesoToCentavos(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter an amount greater than zero.';
                  }
                  if (amount > widget.account.outstandingCentavos) {
                    return 'Payment cannot exceed the remaining balance.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                isExpanded: true,
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
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(formatBusinessDate(_date)),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record payment')),
      ],
    );
  }
}

String _ranges(List<OccupiedDateRange> ranges) => ranges
    .map(
      (range) =>
          '${formatBusinessDate(range.startDate)}–${formatBusinessDate(range.endDateExclusive.addDays(-1))}',
    )
    .join(', ');
