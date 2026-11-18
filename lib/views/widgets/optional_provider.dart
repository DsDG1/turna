// Flutter imports:
import 'package:flutter/widgets.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/di/injection.dart';

/// Reads [T] from the nearest ancestor [Provider] when mounted inside a full
/// app tree, falling back to [getIt] only for isolated widget tests or
/// singletons not hoisted into [MultiProvider].
T? readOptionalProvider<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } catch (_) {
    // Fallback for standalone widget tests or services outside MultiProvider.
    return getIt.isRegistered<T>() ? getIt<T>() : null;
  }
}
