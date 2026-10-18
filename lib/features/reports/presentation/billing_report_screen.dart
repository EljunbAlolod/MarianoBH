import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../authentication/application/auth_providers.dart';
import '../../billing/application/monthly_billing_providers.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../rent/application/rent_providers.dart';
import '../../water/application/water_providers.dart';
import '../application/billing_pdf_generator.dart';
import '../application/billing_report_providers.dart';
import '../domain/billing_report_assembler.dart';
import '../domain/billing_report_models.dart';

class BillingReportScreen extends ConsumerWidget {
  const BillingReportScreen({required this.cycleId, super.key});

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
    final electricity = ref.watch(electricityBillingRecordsProvider(ownerId));
    final water = ref.watch(waterBillingRecordsProvider(ownerId));
    final rent = ref.watch(rentBillingRecordsProvider(ownerId));
    final sources = <AsyncValue<Object?>>[
      cycles,
      controls,
      accounts,
      payments,
      electricity,
      water,
      rent,
    ];
    final failure = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF reports')),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Report records could not be loaded',
            message: propertyErrorMessage(failure.error!),
            actionLabel: 'Try again',
            onAction: () => _invalidate(ref, ownerId),
          ),
        ),
      );
    }
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF reports')),
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
        appBar: AppBar(title: const Text('PDF reports')),
        body: const AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Finalized bill not found',
            message: 'Open a billing-history record before generating a PDF.',
          ),
        ),
      );
    }
    final electricityRecord = electricity.requireValue
        .where((item) => item.billingRecordId == cycle.electricityRecordId)
        .firstOrNull;
    final waterRecord = water.requireValue
        .where((item) => item.waterRecordId == cycle.waterRecordId)
        .firstOrNull;
    final rentRecord = rent.requireValue
        .where((item) => item.rentRecordId == cycle.rentRecordId)
        .firstOrNull;
    if (electricityRecord == null ||
        waterRecord == null ||
        rentRecord == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF reports')),
        body: const AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.link_off_rounded,
            title: 'Source snapshot unavailable',
            message: 'This report needs the immutable electricity, water, and rent records referenced by the finalized bill.',
          ),
        ),
      );
    }
    try {
      final report = const BillingReportAssembler().assemble(
        houseName: workspace.houseName,
        cycle: cycle,
        control: control,
        accounts: accounts.requireValue,
        payments: payments.requireValue,
        electricity: electricityRecord,
        water: waterRecord,
        rent: rentRecord,
        generatedOn: BusinessDate.todayInManila(),
      );
      return _ReportWorkspace(
        key: ValueKey(
          '${cycle.billingCycleId}-${control.updatedAt.microsecondsSinceEpoch}',
        ),
        report: report,
        generator: ref.watch(billingPdfGeneratorProvider),
      );
    } catch (error) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF reports')),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.error_outline_rounded,
            title: 'Report could not be prepared',
            message: propertyErrorMessage(error),
            actionLabel: 'Try again',
            onAction: () => _invalidate(ref, ownerId),
          ),
        ),
      );
    }
  }

  void _invalidate(WidgetRef ref, String ownerId) {
    ref.invalidate(monthlyBillingCyclesProvider(ownerId));
    ref.invalidate(billingCycleControlsProvider(ownerId));
    ref.invalidate(boarderBillAccountsProvider(ownerId));
    ref.invalidate(paymentRecordsProvider(ownerId));
    ref.invalidate(electricityBillingRecordsProvider(ownerId));
    ref.invalidate(waterBillingRecordsProvider(ownerId));
    ref.invalidate(rentBillingRecordsProvider(ownerId));
  }
}

class _ReportWorkspace extends StatefulWidget {
  const _ReportWorkspace({
    required this.report,
    required this.generator,
    super.key,
  });

  final BillingReportSnapshot report;
  final BillingPdfGenerator generator;

  @override
  State<_ReportWorkspace> createState() => _ReportWorkspaceState();
}

class _ReportWorkspaceState extends State<_ReportWorkspace> {
  BillingReportDocumentType _type = BillingReportDocumentType.monthlySummary;
  String? _boarderId;
  Uint8List? _bytes;
  Object? _generationError;
  bool _generating = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _boarderId = widget.report.boarders.firstOrNull?.statement.boarderId;
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _generationError = null;
      _bytes = null;
    });
    try {
      final bytes = await widget.generator.build(
        report: widget.report,
        type: _type,
        boarderId: _boarderId,
      );
      if (mounted) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted) setState(() => _generationError = error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String get _fileName => widget.generator.fileName(
    report: widget.report,
    type: _type,
    boarderId: _boarderId,
  );

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _acting) return;
    setState(() => _acting = true);
    try {
      final opened = await Printing.layoutPdf(
        name: _fileName,
        format: widget.generator.pageFormat(_type),
        dynamicLayout: false,
        onLayout: (format) async => bytes,
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
          title: 'Share billing PDF',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) {
        final message = switch (result.status) {
          ShareResultStatus.success => 'PDF handed to the selected app.',
          ShareResultStatus.dismissed => 'The share sheet was closed.',
          ShareResultStatus.unavailable => 'The share sheet was opened.',
        };
        showPropertyMessage(context, message);
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
    return Scaffold(
      appBar: AppBar(title: const Text('PDF reports')),
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
                      Text(
                        'Create a billing PDF',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Preview the finalized snapshot before saving or opening Android\'s share sheet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<
                                BillingReportDocumentType
                              >(
                                key: const Key('report-type-field'),
                                isExpanded: true,
                                initialValue: _type,
                                decoration: const InputDecoration(
                                  labelText: 'PDF contents',
                                  prefixIcon: Icon(Icons.description_outlined),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: BillingReportDocumentType
                                        .monthlySummary,
                                    child: Text('Monthly house summary'),
                                  ),
                                  DropdownMenuItem(
                                    value: BillingReportDocumentType
                                        .combinedBoarderStatements,
                                    child: Text('All boarder statements'),
                                  ),
                                  DropdownMenuItem(
                                    value: BillingReportDocumentType
                                        .individualBoarderStatement,
                                    child: Text('One boarder statement'),
                                  ),
                                ],
                                onChanged: _acting
                                    ? null
                                    : (value) {
                                        if (value == null || value == _type) {
                                          return;
                                        }
                                        _type = value;
                                        _generate();
                                      },
                              ),
                              if (_type ==
                                  BillingReportDocumentType
                                      .individualBoarderStatement) ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  key: const Key('report-boarder-field'),
                                  isExpanded: true,
                                  initialValue: _boarderId,
                                  decoration: const InputDecoration(
                                    labelText: 'Boarder',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  items: widget.report.boarders
                                      .map(
                                        (boarder) => DropdownMenuItem(
                                          value: boarder.statement.boarderId,
                                          child: Text(
                                            boarder.statement.boarderName,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _acting
                                      ? null
                                      : (value) {
                                          if (value == null ||
                                              value == _boarderId) {
                                            return;
                                          }
                                          _boarderId = value;
                                          _generate();
                                        },
                                ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                _fileName,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked =
                                      constraints.maxWidth < 560 ||
                                      MediaQuery.textScalerOf(context)
                                              .scale(16) >
                                          20;
                                  final save = FilledButton.tonalIcon(
                                    key: const Key('save-pdf-button'),
                                    onPressed: _bytes == null || _acting
                                        ? null
                                        : _save,
                                    icon: const Icon(Icons.save_alt_rounded),
                                    label: const Text('Save PDF'),
                                  );
                                  final share = Builder(
                                    builder: (buttonContext) =>
                                        FilledButton.icon(
                                          key: const Key('share-pdf-button'),
                                          onPressed: _bytes == null || _acting
                                              ? null
                                              : () => _share(buttonContext),
                                          icon: const Icon(
                                            Icons.share_outlined,
                                          ),
                                          label: const Text(
                                            'Share to Messenger / Other Apps',
                                          ),
                                        ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        save,
                                        const SizedBox(height: 8),
                                        share,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: save),
                                      const SizedBox(width: 10),
                                      Expanded(child: share),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Save PDF opens Android\'s system dialog; choose "Save as PDF". Sharing opens the native share sheet so you can select Messenger or another supported app. The app does not post directly to a group chat.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(flex: 6, child: _preview()),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (_generating) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Preparing PDF preview...'),
          ],
        ),
      );
    }
    if (_generationError != null) {
      return AdaptivePageBody(
        child: PropertyStatePanel(
          icon: Icons.error_outline_rounded,
          title: 'PDF could not be generated',
          message: propertyErrorMessage(_generationError!),
          actionLabel: 'Try again',
          onAction: _generate,
        ),
      );
    }
    final bytes = _bytes!;
    return Semantics(
      label: 'PDF preview for $_fileName',
      child: PdfPreview(
        key: ValueKey('$_type-$_boarderId-${bytes.length}'),
        build: (format) async => bytes,
        initialPageFormat: widget.generator.pageFormat(_type),
        pageFormats: {'A4': widget.generator.pageFormat(_type)},
        pdfFileName: _fileName,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        useActions: false,
        dynamicLayout: false,
        maxPageWidth: 850,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => PropertyStatePanel(
          icon: Icons.broken_image_outlined,
          title: 'Preview unavailable',
          message: propertyErrorMessage(error),
        ),
        scrollViewDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
      ),
    );
  }
}
