import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_providers.dart';
import '../../domain/auth_repository.dart';

/// A "Continue with Google" action that starts the Google sign-in flow.
///
/// Google sign-in is only available on Android and iOS. Use [isSupported] to
/// decide whether to show it; the build returns nothing elsewhere.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({
    super.key,
    required this.onError,
    this.enabled = true,
  });

  /// Called with a friendly message when Google sign-in fails.
  final ValueChanged<String> onError;

  /// Whether the button can be pressed.
  final bool enabled;

  /// Whether the current platform supports Google sign-in.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthException catch (error) {
      if (mounted) widget.onError(error.message);
    } catch (_) {
      if (mounted) {
        widget.onError('Google sign-in could not be completed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: widget.enabled && !_busy ? _signIn : null,
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : const Icon(Icons.login_rounded),
      label: const Text('Continue with Google'),
    );
  }
}

/// A horizontal "or" separator between sign-in options.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
