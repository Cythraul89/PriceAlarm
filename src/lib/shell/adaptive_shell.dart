import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Below this width: bottom navigation; at or above: navigation rail.
const double kDesktopBreakpoint = 600;

/// Above this width the rail shows its labels.
const double kExtendedRailBreakpoint = 1200;

class ShellDestination {
  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const kShellDestinations = [
  ShellDestination('Items', Icons.sell_outlined, Icons.sell),
  ShellDestination('Settings', Icons.settings_outlined, Icons.settings),
];

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth < kDesktopBreakpoint
        ? MobileShell(navigationShell: navigationShell, onSelect: _select)
        : DesktopShell(
            navigationShell: navigationShell,
            onSelect: _select,
            extended: constraints.maxWidth >= kExtendedRailBreakpoint,
          ),
  );

  // Re-selecting the active tab returns to its root, the usual expectation.
  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );
}
