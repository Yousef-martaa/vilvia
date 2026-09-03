import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/account/data/account_api_client.dart';
import 'package:vilvia/features/auth/data/auth_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.authService,
    required this.accountUserId,
    this.apiClient,
    this.apiClientFactory,
  });

  final AuthService authService;
  final String accountUserId;
  final AccountApiClient? apiClient;
  final AccountApiClient Function()? apiClientFactory;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountApiClient _apiClient;
  late final bool _ownsApiClient;
  StreamSubscription<AuthState>? _authSubscription;
  int _authGeneration = 0;
  bool _accessRevoked = false;
  bool _isSubmitting = false;
  bool _deletionAccepted = false;
  bool _isSigningOut = false;
  bool _signOutFailed = false;

  @override
  void initState() {
    super.initState();
    _ownsApiClient = widget.apiClient == null;
    _apiClient =
        widget.apiClient ??
        widget.apiClientFactory?.call() ??
        AccountApiClient(
          accessTokenProvider: () =>
              widget.authService.currentSession?.accessToken,
        );
    if (widget.authService.currentSession?.user.id != widget.accountUserId) {
      _accessRevoked = true;
      return;
    }
    _authSubscription = widget.authService.onAuthStateChange.listen(
      _handleAuthState,
    );
  }

  void _handleAuthState(AuthState state) {
    if (state.session?.user.id != widget.accountUserId) _revokeAccess();
  }

  void _revokeAccess() {
    if (_accessRevoked) return;
    _accessRevoked = true;
    _authGeneration++;
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _isSigningOut = false;
    });
    final route = ModalRoute.of(context);
    if (route == null || route.isFirst) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  Future<void> _showDeletionConfirmation() async {
    if (_accessRevoked || _isSubmitting || _deletionAccepted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This is destructive. Vilvia will remove your Profile, authored '
          'Posts, authored Comments, reactions you created, Reports you '
          'created, and threads below your authored Posts through existing '
          'database cascades.\n\nYour request is processed asynchronously '
          'and deletion may not complete immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _submitDeletion();
  }

  Future<void> _submitDeletion() async {
    if (_accessRevoked || _isSubmitting || _deletionAccepted) return;
    final initiatingUserId = widget.accountUserId;
    final authGeneration = _authGeneration;
    if (widget.authService.currentSession?.user.id != initiatingUserId) {
      _revokeAccess();
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _apiClient.requestAccountDeletion();
      if (!_isCurrent(initiatingUserId, authGeneration)) return;
      setState(() {
        _deletionAccepted = true;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!_isCurrent(initiatingUserId, authGeneration)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not request account deletion. Try again.'),
        ),
      );
      return;
    } finally {
      if (!_deletionAccepted && _isCurrent(initiatingUserId, authGeneration)) {
        setState(() => _isSubmitting = false);
      }
    }
    await _attemptSignOut(initiatingUserId, authGeneration);
  }

  Future<void> _attemptSignOut(String userId, int generation) async {
    if (!_deletionAccepted ||
        _isSigningOut ||
        !_isCurrent(userId, generation)) {
      return;
    }
    setState(() {
      _isSigningOut = true;
      _signOutFailed = false;
    });
    try {
      await widget.authService.signOut();
    } catch (_) {
      _showSignOutFailure(userId, generation);
      return;
    }
    // AuthService sign-out is only complete once its local session has been
    // cleared. Treat a successful Future that leaves this user current as a
    // local sign-out failure rather than leaving an endless progress state.
    _showSignOutFailure(userId, generation);
  }

  void _showSignOutFailure(String userId, int generation) {
    if (!_isCurrent(userId, generation) || !mounted) return;
    setState(() {
      _isSigningOut = false;
      _signOutFailed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Deletion was requested, but sign-out failed. Please sign out.',
        ),
      ),
    );
  }

  bool _isCurrent(String userId, int generation) =>
      mounted &&
      !_accessRevoked &&
      generation == _authGeneration &&
      widget.authService.currentSession?.user.id == userId;

  @override
  void dispose() {
    _authSubscription?.cancel();
    if (_ownsApiClient) _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accessRevoked) return const SizedBox.shrink();
    final session = widget.authService.currentSession;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Signed in as', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(session?.user.email ?? ''),
            const SizedBox(height: 24),
            if (!_deletionAccepted)
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : widget.authService.signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            const SizedBox(height: 32),
            Text(
              'Delete account',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Deletion permanently removes your account and authored '
              'community content. Requests are processed asynchronously.',
            ),
            const SizedBox(height: 12),
            if (_deletionAccepted) ...[
              const Text('Deletion request accepted.'),
              const SizedBox(height: 12),
              if (_isSigningOut)
                const Center(child: CircularProgressIndicator())
              else if (_signOutFailed)
                FilledButton.icon(
                  onPressed: () =>
                      _attemptSignOut(widget.accountUserId, _authGeneration),
                  icon: const Icon(Icons.logout),
                  label: const Text('Retry sign out'),
                ),
            ] else
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _showDeletionConfirmation,
                icon: _isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever),
                label: Text(
                  _isSubmitting ? 'Requesting deletion…' : 'Delete account',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
