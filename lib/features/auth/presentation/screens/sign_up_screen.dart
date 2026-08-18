import 'package:flutter/material.dart';

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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;
  bool _awaitingEmailConfirmation = false;
  Gender? _gender;

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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Validated here, before Supabase's signUp() is ever called: an empty
    // or too-long first name would otherwise still create the Auth user,
    // then fail bootstrap afterwards with a 422 -- leaving an
    // authenticated account with no Profile for no reason. The backend's
    // Pydantic validation (1-200 chars) remains the authoritative check;
    // this only avoids creating an account we already know it will
    // reject.
    final firstName = _firstNameController.text.trim();
    if (firstName.isEmpty || firstName.length > 200) {
      setState(() {
        _error = 'Please enter a first name (1-200 characters).';
      });
      return;
    }

    if (_gender == null) {
      setState(() {
        _error = 'Please select a gender.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final response = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.session != null) {
        // Signed in immediately: finish provisioning the Profile now,
        // while the first name just typed on this screen is still
        // available -- see the class doc for why this matters.
        await _profileApiClient.bootstrap(
          firstName: firstName,
          gender: _gender!,
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
        _error = e.toString();
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
                      'Check your email to confirm your account, then come '
                      'back and sign in.',
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
                    const SizedBox(height: 16),
                    Text('Gender', style: textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<Gender>(
                      segments: const [
                        ButtonSegment(
                            value: Gender.male, label: Text('Male')),
                        ButtonSegment(
                            value: Gender.female, label: Text('Female')),
                      ],
                      selected: _gender == null ? const {} : {_gender!},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (selected) {
                        setState(() {
                          _gender = selected.isEmpty ? null : selected.first;
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
