import 'package:flutter/material.dart';

/// Top branding row: the approved Vilvia logo (icon + wordmark).
///
/// No notifications bell or profile avatar is shown — there is no
/// notifications or profile backend yet, and rendering those controls with
/// no behavior behind them would be a false affordance.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Image(
        image: AssetImage('assets/brand/vilvia_logo.png'),
        height: 96,
        fit: BoxFit.contain,
      ),
    );
  }
}
