import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/brand_mark.dart';
import '../application/app_session_controller.dart';
import '../application/auth_providers.dart';

class SessionProblemScreen extends ConsumerStatefulWidget {
  const SessionProblemScreen({super.key});

  @override
  ConsumerState<SessionProblemScreen> createState() =>
      _SessionProblemScreenState();
}

class _SessionProblemScreenState extends ConsumerState<SessionProblemScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await ref.read(appSessionProvider).retry();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appSessionProvider).state;
    final offline = state.status == AppSessionStatus.offline;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const BrandMark(),
                  const SizedBox(height: 38),
                  Icon(
                    offline ? Icons.cloud_off_rounded : Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    offline
                        ? 'You appear to be offline'
                        : 'Account check failed',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.message ?? 'The secure owner record could not be checked. Try again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_busy ? 'Checking…' : 'Try again'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
