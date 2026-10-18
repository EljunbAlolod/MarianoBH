import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../water/presentation/water_formatters.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_models.dart';
import '../domain/utility_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class UtilityBillingDetailScreen extends ConsumerWidget {
  const UtilityBillingDetailScreen({required this.billingBatchId, super.key});

  final String billingBatchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(appSessionProvider).state.workspace;
    if (workspace == null) {
      return const Scaffold(
        body: PropertyStatePanel(
          icon: Icons.lock_outline,
          title: 'Workspace unavailable',
          message: 'Return to the dashboard and try again.',
        ),
      );
    }
    final ownerId = workspace.ownerUid;
    final batches = ref.watch(utilityBillingBatchesProvider(ownerId));
    final accounts = ref.watch(utilityRoomBillAccountsProvider(ownerId));
    final payments = ref.watch(utilityRoomPaymentRecordsProvider(ownerId));
    final values = <AsyncValue<Object?>>[batches, accounts, payments];
    final failure = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room utility bill')),
        body: SafeArea(
          child: AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.cloud_off_outlined,
              title: 'Bill could not be loaded',
              message: propertyErrorMessage(failure.error!),
              actionLabel: 'Try again',
              onAction: () {
                ref.invalidate(utilityBillingBatchesProvider(ownerId));
                ref.invalidate(utilityRoomBillAccountsProvider(ownerId));
                ref.invalidate(utilityRoomPaymentRecordsProvider(ownerId));
              },
            ),
          ),
        ),
      );
    }
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room utility bill')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final batch = batches.requireValue
        .where((item) => item.billingBatchId == billingBatchId)
        .firstOrNull;
    if (batch == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room utility bill')),
        body: SafeArea(
          child: AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.search_off_outlined,
              title: 'Bill not found',
              message: 'It may not have synchronized yet.',
              actionLabel: 'Back to created bills',
              onAction: () => context.go('/billing/created'),
            ),
          ),
        ),
      );
    }
    return _Details(
      ownerId: ownerId,
      batch: batch,
      accounts: accounts.requireValue
          .where((item) => item.billingBatchId == billingBatchId)
          .toList(growable: false),
      payments: payments.requireValue
          .where((item) => item.billingBatchId == billingBatchId)
          .toList(growable: false),
    );
  }
}

class _Details extends ConsumerStatefulWidget {
  const _Details({
    required this.ownerId,
    required this.batch,
    required this.accounts,
    required this.payments,
  });

  final String ownerId;
  final UtilityBillingBatch batch;
  final List<UtilityRoomBillAccount> accounts;
  final List<UtilityRoomPaymentRecord> payments;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  String? _savingRoomId;

  Future<void> _recordPayment(UtilityRoomBillAccount account) async {
    final request = await showDialog<_PaymentRequest>(
      context: context,
      builder: (context) => _UtilityRoomPaymentDialog(account: account),
    );
    if (request == null || !mounted) return;
    setState(() => _savingRoomId = account.roomId);
    try {
      await ref
          .read(monthlyBillingRepositoryProvider)
          .recordUtilityRoomPayment(
            ownerId: widget.ownerId,
            billingBatchId: widget.batch.billingBatchId,
            roomId: account.roomId,
            amountCentavos: request.amountCentavos,
            paymentDate: request.paymentDate,
            method: request.method,
            notes: request.notes,
          );
      ref.invalidate(utilityRoomBillAccountsProvider(widget.ownerId));
      ref.invalidate(utilityRoomPaymentRecordsProvider(widget.ownerId));
      if (mounted) showPropertyMessage(context, 'Room payment recorded.');
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingRoomId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final colors = Theme.of(context).colorScheme;
    final accountsByRoom = {
      for (final account in widget.accounts) account.roomId: account,
    };
    final paymentsByRoom = <String, List<UtilityRoomPaymentRecord>>{};
    for (final payment in widget.payments) {
      paymentsByRoom.putIfAbsent(payment.roomId, () => []).add(payment);
    }
    final totalPaid = widget.accounts.fold<int>(
      0,
      (sum, account) => sum + account.totalPaidCentavos,
    );
    final overallStatus = utilityBillingPaymentStatus(widget.accounts);
    return Scaffold(
      appBar: AppBar(title: const Text('Room utility bill')),
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
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            batch.billingBatchReference,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Created ${formatBusinessDate(batch.issuedOn)}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                      PaymentStatusPill(status: overallStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    key: const Key('open-utility-bill-pdf'),
                    onPressed: () => context.push(
                      '/billing/utility/${Uri.encodeComponent(batch.billingBatchId)}/pdf',
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Preview, save, or share PDF'),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          BillingValueRow(
                            label: 'Billed',
                            value: formatPeso(batch.totalBilledCentavos),
                          ),
                          BillingValueRow(
                            label: 'Paid',
                            value: formatPeso(totalPaid),
                          ),
                          BillingValueRow(
                            label: 'Outstanding',
                            value: formatPeso(
                              batch.totalBilledCentavos - totalPaid,
                            ),
                            emphasized: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            batch.electricityBatchReference,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Electricity measurement: ${formatBusinessDate(batch.electricityMeasurementStart)} – ${formatBusinessDate(batch.electricityMeasurementEnd)}',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            batch.waterBatchReference,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Water statement: ${formatWaterPeriod(batch.waterPeriodStart, batch.waterPeriodEndExclusive)}',
                          ),
                          Text(
                            'Received: ${formatBusinessDate(batch.waterReceiptDate)}',
                          ),
                          if (batch.waterReferenceElectricityBatchReference !=
                              null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Water allocation reference: ${batch.waterReferenceElectricityBatchReference}',
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Text('Rent is not included in this bill.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Room bills',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...batch.statements.map((statement) {
                    final account = accountsByRoom[statement.roomId];
                    final roomPayments =
                        paymentsByRoom[statement.roomId] ?? const [];
                    final saving = _savingRoomId == statement.roomId;
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
                            const SizedBox(height: 8),
                            BillingValueRow(
                              label: 'Electricity',
                              value: formatPeso(statement.electricityCentavos),
                            ),
                            BillingValueRow(
                              label: 'Water',
                              value: formatPeso(statement.waterCentavos),
                            ),
                            const Divider(height: 18),
                            BillingValueRow(
                              label: 'Total',
                              value: formatPeso(statement.totalCentavos),
                              emphasized: true,
                            ),
                            if (account == null) ...[
                              const SizedBox(height: 8),
                              const BillingNotice(
                                message: 'The payment account is still synchronizing. Refresh before recording a payment.',
                                isError: true,
                              ),
                            ] else ...[
                              BillingValueRow(
                                label: 'Paid',
                                value: formatPeso(account.totalPaidCentavos),
                              ),
                              BillingValueRow(
                                label: 'Remaining',
                                value: formatPeso(account.outstandingCentavos),
                              ),
                              if (account.outstandingCentavos > 0) ...[
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  key: Key(
                                    'record-utility-payment-${account.roomId}',
                                  ),
                                  onPressed: _savingRoomId == null
                                      ? () => _recordPayment(account)
                                      : null,
                                  icon: saving
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.payments_outlined),
                                  label: Text(
                                    saving
                                        ? 'Recording payment…'
                                        : 'Record payment',
                                  ),
                                ),
                              ],
                            ],
                            if (roomPayments.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Payment history',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              for (final payment in roomPayments)
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
                  const SizedBox(height: 8),
                  if (batch.totalUnallocatedCentavos > 0)
                    BillingValueRow(
                      label: 'Landlady-paid / unallocated',
                      value: formatPeso(batch.totalUnallocatedCentavos),
                    ),
                  if (batch.warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...batch.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: BillingNotice(message: warning),
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

class _UtilityRoomPaymentDialog extends StatefulWidget {
  const _UtilityRoomPaymentDialog({required this.account});

  final UtilityRoomBillAccount account;

  @override
  State<_UtilityRoomPaymentDialog> createState() =>
      _UtilityRoomPaymentDialogState();
}

class _UtilityRoomPaymentDialogState extends State<_UtilityRoomPaymentDialog> {
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
                key: const Key('utility-payment-amount-field'),
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
                    .toList(growable: false),
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
