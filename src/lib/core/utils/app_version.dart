import 'package:package_info_plus/package_info_plus.dart';

/// `0.1.0+42`, or `unknown` when the platform cannot report it.
Future<String> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return 'unknown';
  }
}
