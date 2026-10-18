import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../shared/widgets/inline_message.dart';
import '../../authentication/application/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../domain/owner_repository.dart';

class BoardingHouseSetupScreen extends ConsumerStatefulWidget {
  const BoardingHouseSetupScreen({super.key});

  @override
  ConsumerState<BoardingHouseSetupScreen> createState() =>
      _BoardingHouseSetupScreenState();
}

class _BoardingHouseSetupScreenState
    extends ConsumerState<BoardingHouseSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ownerNameController;
  final _houseNameController = TextEditingController();
  bool _submitting = false;
  bool _signingOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(appSessionProvider).state.user;
    _ownerNameController = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _houseNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final user = ref.read(appSessionProvider).state.user;
    if (user == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final workspace = await ref
          .read(ownerRepositoryProvider)
          .createWorkspace(
            user: user,
            ownerName: _ownerNameController.text,
            houseName: _houseNameController.text,
          );
      await ref.read(appSessionProvider).workspaceCreated(workspace);
    } on OwnerRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Setup could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
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
    final busy = _submitting || _signingOut;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your boarding house'),
        actions: [
          TextButton(
            onPressed: busy ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.home_work_outlined,
                      size: 62,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'One last step',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These details create a private workspace tied to your verified account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (_error != null) ...[
                      InlineMessage(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const Key('setup-owner-name'),
                      controller: _ownerNameController,
                      validator: (value) => Validators.requiredText(
                        value,
                        label: 'Owner name',
                        maxLength: 80,
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Owner name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('setup-house-name'),
                      controller: _houseNameController,
                      validator: (value) => Validators.requiredText(
                        value,
                        label: 'Boarding house name',
                        maxLength: 120,
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Boarding house name',
                        hintText: 'e.g. Mariano Boarding House',
                        prefixIcon: Icon(Icons.apartment_rounded),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      key: const Key('setup-submit'),
                      onPressed: busy ? null : _submit,
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Create secure workspace'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Default currency: Philippine peso (PHP)\nBusiness timezone: Asia/Manila',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
