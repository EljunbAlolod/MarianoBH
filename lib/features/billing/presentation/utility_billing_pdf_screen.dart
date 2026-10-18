import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../reports/application/billing_report_providers.dart';
import '../../reports/application/utility_billing_pdf_generator.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/utility_billing_models.dart';

class UtilityBillingPdfScreen extends ConsumerWidget {
  const UtilityBillingPdfScreen({required this.billingBatchId, super.key});

  final String billingBatchId;

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
    final batches = ref.watch(utilityBillingBatchesProvider(ownerId));
    final accounts = ref.watch(utilityRoomBillAccountsProvider(ownerId));
    final payments = ref.watch(utilityRoomPaymentRecordsProvider(ownerId));
    final values = <AsyncValue<Object?>>[batches, accounts, payments];
    final failure = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utility bill PDF')),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'PDF records could not be loaded',
            message: propertyErrorMessage(failure.error!),
          ),
        ),
      );
    }
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utility bill PDF')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final batch = batches.requireValue
        .where((item) => item.billingBatchId == billingBatchId)
        .firstOrNull;
    if (batch == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utility bill PDF')),
        body: const AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Finalized bill not found',
            message: 'Open a created bill before generating its PDF.',
          ),
        ),
      );
    }
    final batchAccounts = accounts.requireValue
        .where((item) => item.billingBatchId == billingBatchId)
        .toList(growable: false);
    final batchPayments = payments.requireValue
        .where((item) => item.billingBatchId == billingBatchId)
        .toList(growable: false);
    return _Workspace(
      key: ValueKey(
        '$billingBatchId-${batchAccounts.fold<int>(0, (sum, item) => sum + item.totalPaidCentavos)}',
      ),
      houseName: workspace.houseName,
      batch: batch,
      accounts: batchAccounts,
      payments: batchPayments,
      generator: ref.watch(utilityBillingPdfGeneratorProvider),
    );
  }
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    required this.houseName,
    required this.batch,
    required this.accounts,
    required this.payments,
    required this.generator,
    super.key,
  });

  final String houseName;
  final UtilityBillingBatch batch;
  final List<UtilityRoomBillAccount> accounts;
  final List<UtilityRoomPaymentRecord> payments;
  final UtilityBillingPdfGenerator generator;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  UtilityBillingPdfDocumentType _type = UtilityBillingPdfDocumentType.summary;
  String? _roomId;
  Uint8List? _bytes;
  Object? _error;
  bool _generating = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _roomId = widget.batch.statements.firstOrNull?.roomId;
    _generate();
  }

  RoomUtilityBillStatement? get _selectedRoom => widget.batch.statements
      .where((statement) => statement.roomId == _roomId)
      .firstOrNull;

  String get _fileName => widget.generator.fileName(
    houseName: widget.houseName,
    batch: widget.batch,
    type: _type,
    roomName: _selectedRoom?.roomName,
  );

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
      _bytes = null;
    });
    try {
      final bytes = await widget.generator.build(
        houseName: widget.houseName,
        batch: widget.batch,
        accounts: widget.accounts,
        payments: widget.payments,
        type: _type,
        roomId: _roomId,
      );
      if (mounted) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _acting) return;
    setState(() => _acting = true);
    try {
      final opened = await Printing.layoutPdf(
        name: _fileName,
        format: widget.generator.pageFormat(_type),
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
      if (mounted) {
        showPropertyMessage(
          context,
          opened
              ? 'Android completed the save / print flow.'
              : 'The save / print flow was closed.',
        );
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final bytes = _bytes;
    if (bytes == null || _acting) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    setState(() => _acting = true);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
          fileNameOverrides: [_fileName],
          title: 'Share room utility bill PDF',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) {
        showPropertyMessage(context, switch (result.status) {
          ShareResultStatus.success => 'PDF handed to the selected app.',
          ShareResultStatus.dismissed => 'The share sheet was closed.',
          ShareResultStatus.unavailable => 'The share sheet was opened.',
        });
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _bytes != null && !_generating && !_acting;
    return Scaffold(
      appBar: AppBar(title: const Text('Utility bill PDF')),
      body: SafeArea(
        child: Column(
          children: [
            Flexible(
              flex: 5,
              child: SingleChildScrollView(
                child: AdaptivePageBody(
                  maxWidth: 1000,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageIntro(
                        title: widget.batch.billingBatchReference,
                        subtitle: 'Generate from the saved snapshot. Electricity and water periods stay separate; rent is not included.',
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<UtilityBillingPdfDocumentType>(
                        key: const Key('utility-pdf-type-field'),
                        initialValue: _type,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'PDF type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: UtilityBillingPdfDocumentType.summary,
                            child: Text('Billing summary'),
                          ),
                          DropdownMenuItem(
                            value:
                                UtilityBillingPdfDocumentType.allRoomStatements,
                            child: Text('All room statements'),
                          ),
                          DropdownMenuItem(
                            value: UtilityBillingPdfDocumentType
                                .individualRoomStatement,
                            child: Text('One room statement'),
                          ),
                        ],
                        onChanged: _acting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _type = value);
                                _generate();
                              },
                      ),
                      if (_type ==
                          UtilityBillingPdfDocumentType
                              .individualRoomStatement) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const Key('utility-pdf-room-field'),
                          initialValue: _roomId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Room'),
                          items: widget.batch.statements
                              .map(
                                (statement) => DropdownMenuItem(
                                  value: statement.roomId,
                                  child: Text(statement.roomName),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _acting
                              ? null
                              : (value) {
                                  setState(() => _roomId = value);
                                  _generate();
                                },
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (_generating) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('Preparing PDF preview...'),
                      ],
                      if (_error != null)
                        PropertyStatePanel(
                          icon: Icons.error_outline_rounded,
                          title: 'PDF could not be generated',
                          message: propertyErrorMessage(_error!),
                          actionLabel: 'Try again',
                          onAction: _generate,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _fileName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked =
                              constraints.maxWidth < 560 ||
                              MediaQuery.textScalerOf(context).scale(16) > 20;
                          final share = Builder(
                            builder: (buttonContext) => FilledButton.icon(
                              key: const Key('share-utility-pdf-button'),
                              onPressed: ready
                                  ? () => _share(buttonContext)
                                  : null,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Share to apps'),
                            ),
                          );
                          final save = OutlinedButton.icon(
                            key: const Key('save-utility-pdf-button'),
                            onPressed: ready ? _save : null,
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Save / print PDF'),
                          );
                          if (stacked) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                share,
                                const SizedBox(height: 8),
                                save,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: share),
                              const SizedBox(width: 10),
                              Expanded(child: save),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_bytes != null)
              Flexible(
                flex: 6,
                child: Semantics(
                  label: 'Preview of $_fileName',
                  child: PdfPreview(
                    key: const Key('utility-pdf-preview'),
                    build: (_) async => _bytes!,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    useActions: false,
                    pdfFileName: _fileName,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
