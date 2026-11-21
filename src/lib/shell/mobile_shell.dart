import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'adaptive_shell.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({
    super.key,
    required this.navigationShell,
    required this.onSelect,
  });

  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: onSelect,
      destinations: [
        for (final d in kShellDestinations)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: d.label,
          ),
      ],
    ),
  );
}
