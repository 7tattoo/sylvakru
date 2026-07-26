import 'package:flutter/widgets.dart';

/// Server clients (webdav/subsonic/navidrome/emby) run deep in the data
/// layer with no BuildContext of their own, so failures can't call
/// showCenterMessage() directly. They report through here instead;
/// [ViewEntry] is the single place that listens and surfaces
/// [lastNetworkErrorMessage] to the user.
final networkErrorNotifier = ValueNotifier(0);
String? lastNetworkErrorMessage;

DateTime? _lastReportTime;

/// Debounced globally across all sources: a sync loop hitting a downed
/// server for hundreds of songs should surface one toast, not hundreds.
void reportNetworkError(String sourceLabel, String message) {
  final now = DateTime.now();
  if (_lastReportTime != null &&
      now.difference(_lastReportTime!) < const Duration(seconds: 5)) {
    return;
  }
  _lastReportTime = now;
  lastNetworkErrorMessage = '$sourceLabel: $message';
  // ensureInitialized：纯 Dart 测试环境（无 runApp）里 instance 会直接抛错
  WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
    networkErrorNotifier.value++;
  });
}
