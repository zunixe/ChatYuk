import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_provider.dart';
export '../admin_provider.dart';

/// AdminProvider yang dikelola Riverpod (build admin-only).
///
/// Di-reuse apa adanya (ChangeNotifier besar lintas-domain) supaya 100+
/// getter/method di panel admin tidak perlu dipetakan ulang ke state baru.
/// Riverpod membuat instance lazily + membuangnya saat container dispose.
final adminProvider = ChangeNotifierProvider<AdminProvider>((ref) {
  final provider = AdminProvider();
  ref.onDispose(provider.dispose);
  return provider;
});
