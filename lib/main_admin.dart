// ============================================================
// Entry BUILD ADMIN — JANGAN PERNAH dipakai untuk rilis store.
//
// Build:
//   flutter build apk --release --flavor admin -t lib/main_admin.dart \
//     --dart-define=APP_FLAVOR=apkpure \
//     --obfuscate --split-debug-info=build/app/symbols
//
// Build rilis (APKPure/Play/Uptodown) memakai entry default
// lib/main.dart — tanpa flag -t apa pun.
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'admin/admin_wiring.dart';
import 'firebase_options_admin.dart';
import 'main.dart' show bootstrap;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    wireAdmin();
  } catch (e, st) {
    debugPrint('[WIRE-CRASH] $e\n$st');
    rethrow;
  }
  await bootstrap(firebaseOptions: DefaultFirebaseOptionsAdmin.currentPlatform);
}
