import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../../shared/widgets/app_components.dart';
import '../../property_management/presentation/widgets/property_ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingOut = false;
  String? _error;

  Future<void> _signOut() async {
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider).state;
    final workspace = session.workspace;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            AdaptivePageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageIntro(
                    title: 'Your workspace',
                    subtitle: 'Account details and the defaults used for your records.',
                    icon: Icons.tune_rounded,
                  ),
                  const SectionHeader('Owner account'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_outline_rounded),
                          title: Text(workspace?.ownerName ?? 'Owner'),
                          subtitle: Text(session.user?.email ?? ''),
                        ),
                        const Divider(height: 1),
                        const ListTile(
                          leading: Icon(Icons.mark_email_read_outlined),
                          title: Text('Email verified'),
                          trailing: Icon(Icons.check_circle_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Business defaults'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: const Text('Currency'),
                          subtitle: Text(workspace?.currencyCode ?? 'PHP'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule_rounded),
                          title: const Text('Business timezone'),
                          subtitle: Text(
                            workspace?.businessTimeZone ?? 'Asia/Manila',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    icon: _signingOut
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
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
