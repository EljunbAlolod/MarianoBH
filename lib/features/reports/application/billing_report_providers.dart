import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_pdf_generator.dart';
import 'utility_billing_pdf_generator.dart';

final billingPdfGeneratorProvider = Provider<BillingPdfGenerator>(
  (ref) => const BillingPdfGenerator(),
);

final utilityBillingPdfGeneratorProvider = Provider<UtilityBillingPdfGenerator>(
  (ref) => const UtilityBillingPdfGenerator(),
);
