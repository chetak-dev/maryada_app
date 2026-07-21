import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// A one-tap light/dark toggle for app bars. Flips to the opposite of the
/// currently-shown brightness and persists the choice.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
      onPressed: () => ThemeController.instance
          .set(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
