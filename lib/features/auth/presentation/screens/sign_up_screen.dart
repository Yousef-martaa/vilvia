import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Minimal email/password sign-up. Supabase's `signUp()` has two valid
/// outcomes -- a session (confirmation not required, or already off) or
/// no session with a pending confirmation email -- and this screen must
/// not treat those as the same thing. Only the session outcome runs the
/// Profile bootstrap; the no-session outcome shows a "check your email"
/// state and does not call bootstrap at all yet.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authService, this.profileApiClient});

  final AuthService? authService;
  final ProfileApiClient? profileApiClient;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late final AuthService _authService;
  late final ProfileApiClient _profileApiClient;
  late final bool _ownsProfileClient;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;
  bool _awaitingEmailConfirmation = false;
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _mapErrorMessage(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    return 'Could not create account. Please try again.';
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (firstName.isEmpty || firstName.length > 200) {
      setState(() => _error = 'Please enter a first name (1-200 characters).');
      return;
    }
    if (lastName.isEmpty || lastName.length > 200) {
      setState(() => _error = 'Please enter a last name (1-200 characters).');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Please enter an email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        userMetadata: {
          'first_name': firstName,
          'last_name': lastName,
          if (_parentRole != null) 'parent_role': _parentRole!.toJson(),
        },
      );

      if (!mounted) return;

      if (response.session != null) {
        await _profileApiClient.bootstrap(
          firstName: firstName,
          lastName: lastName,
          parentRole: _parentRole,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      // A user was created but there is no session yet: email
      // confirmation is required. This is a normal, successful outcome,
      // not an error -- there is nothing to bootstrap until the user
      // actually has a session.
      setState(() {
        _isSubmitting = false;
        _awaitingEmailConfirmation = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _mapErrorMessage(e);
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
                  Text('Create your account', style: textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  if (_awaitingEmailConfirmation)
                    Text(
                      'If this email is new, we’ve sent a confirmation link. '
                      'If you already have an account, please sign in instead.',
                      style: textTheme.bodyLarge,
                    )
                  else ...[
                    TextField(
                      controller: _firstNameController,
                      decoration:
                          const InputDecoration(labelText: 'First name'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lastNameController,
                      decoration:
                          const InputDecoration(labelText: 'Last name'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
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
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordController,
                      decoration:
                          const InputDecoration(labelText: 'Confirm Password'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
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
                            : const Text('Sign Up'),
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
