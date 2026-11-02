import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/topup_service.dart';
import 'points_provider.dart';

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

final topupProvider = Provider<TopupNotifier>((ref) {
  final n = TopupNotifier();
  // Koin sukses di-credit server → segarkan saldo (kartu YukCoin, counter
  // call). Dulu callback ini TIDAK PERNAH di-wire → saldo stale setelah
  // beli koin sampai ada refresh lain.
  n.service.onCredited = (_) =>
      ref.read(pointsProvider.notifier).refreshWallet();
  return n;
});
