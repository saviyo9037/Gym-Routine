import 'package:flutter/foundation.dart';

/// Debug-only logging. Release builds print nothing, so routine titles,
/// plan names or other user data never reach logcat.
void devLog(String message) {
  if (kDebugMode) debugPrint(message);
}
