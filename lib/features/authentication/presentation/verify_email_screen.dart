import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/inline_message.dart';
import '../application/auth_providers.dart';
import '../domain/auth_repository.dart';
import 'auth_scaffold.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _checking = false;
  bool _resending = false;
  bool _signingOut = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _checkVerification() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    await ref.read(appSessionProvider).refreshUser();
    if (mounted) {
      final verified =
          ref.read(appSessionProvider).state.user?.isEmailVerified ?? false;
      setState(() {
        _checking = false;
        if (!verified) {
          _message =
              'The email is not verified yet. Open the link, then try again.';
          _messageIsError = false;
        }
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendEmailVerification();
      if (mounted) {
        setState(() {
          _message = 'A new verification email has been sent.';
          _messageIsError = false;
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email =
        ref.watch(appSessionProvider).state.user?.email ?? 'your email';
    final busy = _checking || _resending || _signingOut;
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'A verification link was sent to $email.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          const Text(
            'Open the message and tap the verification link. This protects your records before the boarding house workspace is created.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.45),
          ),
          if (_message != null) ...[
            const SizedBox(height: 18),
            InlineMessage(
              message: _message!,
              isError: _messageIsError,
              icon: _messageIsError
                  ? Icons.error_outline
                  : Icons.info_outline_rounded,
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('verification-check'),
            onPressed: busy ? null : _checkVerification,
            child: _checking
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('I have verified my email'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: busy ? null : _resend,
            child: Text(_resending ? 'Sending…' : 'Resend verification email'),
          ),
          TextButton(
            onPressed: busy ? null : _signOut,
            child: Text(
              _signingOut ? 'Signing out…' : 'Use a different account',
            ),
          ),
        ],
      ),
    );
  }
}
