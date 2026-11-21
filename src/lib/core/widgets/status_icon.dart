import 'package:flutter/material.dart';

import '../models/enums.dart';

/// Icon + colour for an offer's last check status.
class CheckStatusIcon extends StatelessWidget {
  const CheckStatusIcon({super.key, required this.status, this.size = 18});

  final CheckStatus? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      null => (Icons.schedule, scheme.onSurfaceVariant),
      CheckStatus.ok => (Icons.check_circle_outline, Colors.green),
      CheckStatus.blocked => (Icons.block, scheme.error),
      CheckStatus.noPrice => (Icons.help_outline, scheme.error),
      CheckStatus.networkError => (Icons.cloud_off, scheme.error),
      CheckStatus.unsupported => (Icons.do_not_disturb_on_outlined, scheme.error),
    };
    return Icon(icon, color: color, size: size);
  }
}

String checkStatusLabel(CheckStatus? status) => switch (status) {
  null => 'not checked yet',
  CheckStatus.ok => 'ok',
  CheckStatus.blocked => 'blocked',
  CheckStatus.noPrice => 'no price found',
  CheckStatus.networkError => 'network error',
  CheckStatus.unsupported => 'unsupported',
};
