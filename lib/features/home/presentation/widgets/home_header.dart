import 'package:flutter/material.dart';

import 'package:vilvia/features/account/data/account_api_client.dart';
import 'package:vilvia/features/account/presentation/screens/account_screen.dart';
import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Top branding row: the approved Vilvia logo, plus a small sign-in-state
/// affordance -- "Sign In" when signed out, or an Account entry showing the
/// account's email when signed in. Reactive via [AuthService]'s own
/// auth-state stream; no separate state-management framework.
///
/// No notifications bell is shown -- there is no notifications backend
/// yet, and rendering a control with no behavior behind it would be a
/// false affordance.
class HomeHeader extends StatefulWidget {
  const HomeHeader({super.key, this.authService, this.accountApiClient});

  final AuthService? authService;
  final AccountApiClient? accountApiClient;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        const Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image(
              image: AssetImage('assets/brand/vilvia_logo.png'),
              height: 96,
              fit: BoxFit.contain,
            ),
          ),
        ),
        StreamBuilder(
          stream: _authService.onAuthStateChange,
          builder: (context, snapshot) {
            final session =
                snapshot.data?.session ?? _authService.currentSession;

            if (session == null) {
              return TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SignInScreen(authService: _authService),
                  ),
                ),
                child: const Text('Sign In'),
              );
            }

            return TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountScreen(
                    authService: _authService,
                    accountUserId: session.user.id,
                    apiClient: widget.accountApiClient,
                  ),
                ),
              ),
              icon: const Icon(
                Icons.account_circle,
                color: VilviaColors.charcoal,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  session.user.email ?? 'Account',
                  style: textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
