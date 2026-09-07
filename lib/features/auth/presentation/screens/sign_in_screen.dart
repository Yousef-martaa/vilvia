import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Minimal email/password sign-in.
///
/// After a successful sign-in, this screen checks whether the account
/// already has a Profile (GET /me). For a returning user this normally
/// succeeds immediately. It can legitimately be missing for a user
/// signing in for the very first time after confirming their email
/// on a different device/session (so the sign-up screen's session
/// never existed to bootstrap from) -- rather than leaving that account
/// stuck, this screen offers an inline "finish setting up" step right
/// here, which is the only place a first name is asked for again.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.authService, this.profileApiClient});

  final AuthService? authService;
  final ProfileApiClient? profileApiClient;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final AuthService _authService;
  late final ProfileApiClient _profileApiClient;
  late final bool _ownsProfileClient;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _finishSetupFirstNameController = TextEditingController();
  final _finishSetupLastNameController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;
  bool _needsProfileSetup = false;
  ParentRole? _parentRole;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _ownsProfileClient = widget.profileApiClient == null;
    _profileApiClient = widget.profileApiClient ??
        ProfileApiClient(
          accessToken: () => _authService.currentSession?.accessToken,
        );
  }

  @override
  void dispose() {
    if (_ownsProfileClient) _profileApiClient.close();
    _emailController.dispose();
    _passwordController.dispose();
    _finishSetupFirstNameController.dispose();
    _finishSetupLastNameController.dispose();
    super.dispose();
  }

  String _mapErrorMessage(Object error, {required String fallback}) {
    if (error is AuthException) {
      return error.message;
    }
    return fallback;
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _authService.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await _finishAfterSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _mapErrorMessage(e, fallback: 'Could not sign in. Please try again.');
      });
    }
  }

  Future<void> _finishAfterSession() async {
    try {
      await _profileApiClient.getMe();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ProfileNotFoundException {
      final metadata = _authService.currentSession?.user.userMetadata;
      final firstName = metadata?['first_name'] as String?;
      final lastName = metadata?['last_name'] as String?;
      final parentRoleStr = metadata?['parent_role'] as String?;
      ParentRole? parentRole;
      if (parentRoleStr != null) {
        try {
          parentRole = ParentRole.fromJson(parentRoleStr);
        } catch (_) {
          parentRole = null;
        }
      }

      // Check if we can auto-bootstrap from metadata
      if (firstName != null &&
          firstName.isNotEmpty &&
          lastName != null &&
          lastName.isNotEmpty) {
        try {
          await _profileApiClient.bootstrap(
            firstName: firstName,
            lastName: lastName,
            parentRole: parentRole,
          );
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        } catch (_) {
          // Auto-bootstrap failed (e.g. transient network or backend error).
          // Present prefilled form with error message so the user can retry.
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
            _error = 'Could not finish setting up your account. Please try again.';
            _finishSetupFirstNameController.text = firstName;
            _finishSetupLastNameController.text = lastName;
            _parentRole = parentRole;
            _needsProfileSetup = true;
          });
          return;
        }
      }

      // Metadata was missing required fields (e.g. legacy account).
      // Prefill whatever fields are available.
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _needsProfileSetup = true;
        if (firstName != null && firstName.isNotEmpty) {
          _finishSetupFirstNameController.text = firstName;
        }
        if (lastName != null && lastName.isNotEmpty) {
          _finishSetupLastNameController.text = lastName;
        }
        if (parentRole != null) {
          _parentRole = parentRole;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _mapErrorMessage(e, fallback: 'Failed to load profile. Please try again.');
      });
    }
  }

  Future<void> _completeSetup() async {
    final firstName = _finishSetupFirstNameController.text.trim();
    final lastName = _finishSetupLastNameController.text.trim();
    if (firstName.isEmpty || firstName.length > 200) {
      setState(() => _error = 'Please enter a first name (1-200 characters).');
      return;
    }
    if (lastName.isEmpty || lastName.length > 200) {
      setState(() => _error = 'Please enter a last name (1-200 characters).');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _profileApiClient.bootstrap(
        firstName: firstName,
        lastName: lastName,
        parentRole: _parentRole,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _mapErrorMessage(e, fallback: 'Failed to complete setup. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: VilviaColors.charcoal),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _needsProfileSetup ? 'Finish setting up' : 'Sign in',
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_needsProfileSetup) ...[
                    Text(
                      "You're signed in, but we still need some details "
                      'to finish setting up your account.',
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _finishSetupFirstNameController,
                      decoration:
                          const InputDecoration(labelText: 'First name'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _finishSetupLastNameController,
                      decoration:
                          const InputDecoration(labelText: 'Last name'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    Text('I am a...', style: textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<ParentRole>(
                      segments: ParentRole.values
                          .map((role) => ButtonSegment(
                                value: role,
                                label: Text(role.label),
                              ))
                          .toList(),
                      selected: _parentRole == null ? const {} : {_parentRole!},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (selected) {
                        setState(() {
                          _parentRole =
                              selected.isEmpty ? null : selected.first;
                        });
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: VilviaColors.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _completeSetup,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: VilviaColors.surface,
                                ),
                              )
                            : const Text('Complete Setup'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration:
                          const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: VilviaColors.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: VilviaColors.surface,
                                ),
                              )
                            : const Text('Sign In'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => SignUpScreen(
                                      authService: _authService,
                                      profileApiClient: widget.profileApiClient,
                                    ),
                                  ),
                                ),
                        child: const Text("Don't have an account? Sign Up"),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
