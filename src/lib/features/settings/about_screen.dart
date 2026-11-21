import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

const kLicenseNotice =
    'PriceAlarm is free software: you can redistribute it and/or modify it '
    'under the terms of the GNU General Public License as published by the '
    'Free Software Foundation, either version 3 of the License, or (at your '
    'option) any later version.';

const kPrivacyNotice =
    'PriceAlarm has no account and no telemetry. All data stays on this '
    'device. The only network traffic is loading the shop pages you add, '
    'once per day per offer, plus when you tap "Check now" or "Test".';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('PriceAlarm', style: theme.textTheme.headlineSmall),
          Text('Version $version'),
          const SizedBox(height: 16),
          Text('Licence', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(kLicenseNotice),
          const SizedBox(height: 16),
          Text('Privacy', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(kPrivacyNotice),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('App logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Open-source licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'PriceAlarm',
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }
}
