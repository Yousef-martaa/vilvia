import 'package:flutter/material.dart';

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
  final _finishSetupNameController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;
  bool _needsProfileSetup = false;
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
    _emailController.dispose();
    _passwordController.dispose();
    _finishSetupNameController.dispose();
    super.dispose();
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
        _error = e.toString();
      });
    }
  }

  Future<void> _finishAfterSession() async {
    try {
      await _profileApiClient.getMe();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ProfileNotFoundException {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _needsProfileSetup = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _completeSetup() async {
    // Same first-name validation as SignUpScreen, applied here before
    // bootstrap is called -- see that screen's _submit() for why this
    // must happen before the network call, not just rely on the
    // backend's 422.
    final firstName = _finishSetupNameController.text.trim();
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
      await _profileApiClient.bootstrap(
        firstName: firstName,
        gender: _gender!,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
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
                  Text(
                    _needsProfileSetup ? 'Finish setting up' : 'Sign in',
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_needsProfileSetup) ...[
                    Text(
                      "You're signed in, but we still need your name and "
                      'gender to finish setting up your account.',
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _finishSetupNameController,
                      decoration:
                          const InputDecoration(labelText: 'First name'),
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
