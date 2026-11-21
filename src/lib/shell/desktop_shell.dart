import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'adaptive_shell.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.navigationShell,
    required this.onSelect,
    required this.extended,
  });

  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: onSelect,
          extended: extended,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          destinations: [
            for (final d in kShellDestinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: Text(d.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: navigationShell),
      ],
    ),
  );
}
