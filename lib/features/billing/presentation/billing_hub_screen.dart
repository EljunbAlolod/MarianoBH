import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_components.dart';
import '../../property_management/presentation/widgets/property_ui.dart';

class BillingHubScreen extends StatelessWidget {
  const BillingHubScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Billing')),
    body: SafeArea(
      child: ListView(
        key: const PageStorageKey('billing-hub-scroll'),
        children: [
          AdaptivePageBody(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageIntro(
                  title: 'Bills made simple',
                  subtitle: 'Prepare utilities, create room bills, then collect payments.',
                  eyebrow: 'BILLING WORKSPACE',
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.push('/billing/monthly/new'),
                  icon: const Icon(Icons.add, size: 24),
                  label: const Text('Create room bills'),
                ),
                const SectionHeader(
                  'Prepare utilities',
                  subtitle:
                      'Electricity and water keep their own statement periods',
                ),
                ActionListItem(
                  key: const Key('electricity-billing-card'),
                  title: 'Electricity',
                  subtitle: 'Meters, readings and reading batches',
                  icon: Icons.bolt_outlined,
                  onTap: () => context.push('/billing/electricity'),
                ),
                ActionListItem(
                  key: const Key('water-billing-card'),
                  title: 'Water',
                  subtitle:
                      'Choose boarders or use summer electricity percentages',
                  icon: Icons.water_drop_outlined,
                  onTap: () => context.push('/billing/water'),
                ),
                const SectionHeader('Collect & review'),
                ActionListItem(
                  key: const Key('monthly-billing-card'),
                  title: 'Room bills & payments',
                  subtitle: 'Billed, collected and outstanding balances',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => context.push('/billing/monthly'),
                ),
                ActionListItem(
                  title: 'Created bills',
                  subtitle: 'Find a bill, record a payment or share its PDF',
                  icon: Icons.folder_open_outlined,
                  onTap: () => context.push('/billing/created'),
                ),
                const SectionHeader(
                  'Fixed monthly rent',
                  subtitle: 'Separate from room utility bills',
                ),
                ActionListItem(
                  key: const Key('rent-billing-card'),
                  title: 'Rent',
                  subtitle:
                      'Coverage, due dates, payments and move-out decisions',
                  icon: Icons.payments_outlined,
                  onTap: () => context.push('/billing/rent'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
