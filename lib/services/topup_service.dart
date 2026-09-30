import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_flavor.dart';
import 'points_service.dart';
import '../utils.dart';

/// Topup YukCoin via Google Play Billing.
///
/// Alur:
///   1. `init()` — sambung Play Billing, muat produk (topup_packages).
///   2. `buy(productId)` — mulai pembelian → Play memproses.
///   3. `purchaseStream` menerima PurchaseDetails.status == purchased →
///      kirim purchaseToken ke server (edge function play-topup-verify) →
///      server verifikasi ke Google Play Developer API → credit coin.
///   4. `completePurchase` tiap transaksi (wajib, agar tak auto-refund).
///
/// Hanya aktif pada build flavor `play` (AppFlavor.topupEnabled). Di luar itu
/// topup = no-op (tombol menampilkan "segera hadir").
class TopupService {
  TopupService._();
  static final TopupService instance = TopupService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool get available => _available;

  bool _ready = false;
  List<ProductDetails> _products = const [];
  List<ProductDetails> get products => _products;

  /// Paket (dari DB) untuk memetakan product_id → coins (UI). Struktur:
  /// [{id, coins, price_idr, bonus_label, play_product_id}].
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> get packages => _packages;

  /// Callback setelah coin berhasil di-credit server.
  void Function(int coins)? onCredited;

  Future<void> init() async {
    if (_ready) return;
    if (!AppFlavor.topupEnabled) return;
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      await _loadPackages();
      final ids = _packages
          .map((p) => p['play_product_id'] as String?)
          .whereType<String>()
          .toList();
      if (ids.isNotEmpty) {
        final resp = await _iap.queryProductDetails(ids.toSet());
        _products = resp.productDetails;
      }
      _sub = _iap.purchaseStream.listen(
        _onPurchase,
        onError: (e) => dlog('[TOPUP] purchase stream error: $e'),
      );
      _ready = true;
    } catch (e) {
      dlog('[TOPUP] init error: $e');
    }
  }

  Future<void> _loadPackages() async {
    try {
      _packages = await PointsService().listTopupPackages();
    } catch (e) {
      dlog('[TOPUP] loadPackages error: $e');
    }
  }

  /// Mulai pembelian (Play memproses; hasil via purchaseStream).
  Future<void> buy(String productId) async {
    final match = _products.where((p) => p.id == productId).toList();
    if (match.isEmpty) {
      dlog('[TOPUP] produk tidak ditemukan: $productId');
      return;
    }
    try {
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: match.first),
      );
    } catch (e) {
      dlog('[TOPUP] buy error: $e');
    }
  }

  Future<void> _onPurchase(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) continue;
      if (p.status == PurchaseStatus.error) {
        dlog('[TOPUP] purchase error: ${p.error}');
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        continue;
      }
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final token = p.verificationData.serverVerificationData;
        try {
          final coins = await PointsService().verifyPlayTopup(
            productId: p.productID,
            purchaseToken: token,
          );
          if (coins > 0) onCredited?.call(coins);
        } catch (e) {
          dlog('[TOPUP] verify error: $e');
        }
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
