import 'package:flutter/material.dart';

import '../alerts/alerts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';

/// The signed-in root: a bottom-navigation shell hosting the Home dashboard,
/// the Alerts feed and Settings. Each tab keeps its own state via [IndexedStack].
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.uid});

  final String? uid;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(uid: widget.uid),
      AlertsScreen(uid: widget.uid),
      SettingsScreen(uid: widget.uid),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
