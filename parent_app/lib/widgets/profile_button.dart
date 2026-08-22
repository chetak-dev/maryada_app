import 'package:flutter/material.dart';

import '../screens/profile/profile_screen.dart';

/// A single profile button (top-right app bar action) used by both the site
/// admin and org-admin surfaces. Opens the [ProfileScreen] with login info,
/// role-appropriate actions and sign out.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Profile',
      icon: const Icon(Icons.account_circle_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
    );
  }
}
