import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/topup_service.dart';

/// Topup Play Billing (Riverpod) — action-only, wrapper [TopupService].
/// Fase B boundary: screen topup dilarang import services/ langsung.
/// `init()` tetap dipanggil composition root (`main.dart`).
class TopupNotifier {
  final TopupService service;
  TopupNotifier([TopupService? service])
      : service = service ?? TopupService.instance;

  Future<void> init() => service.init();
  List<Map<String, dynamic>> get packages => service.packages;
  bool get available => service.available;
  Future<void> buy(String productId) => service.buy(productId);
}

final topupProvider = Provider<TopupNotifier>((_) => TopupNotifier());
