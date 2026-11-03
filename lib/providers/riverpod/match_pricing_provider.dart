import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/gifts.dart';
import '../../services/points_service.dart';

/// Biaya match video dari server (`metered_pricing_public`) — konstanta di
/// `config/gifts.dart` hanya fallback sebelum data tiba / bila offline.
class MatchPricing {
  final int searchCoins;
  final int connectCoins;
  final int freeSeconds;

  const MatchPricing({
    this.searchCoins = kMatchFeeCoins,
    this.connectCoins = kMatchConnectFeeCoins,
    this.freeSeconds = kMatchFreeSeconds,
  });

  factory MatchPricing.fromJson(Map<String, dynamic> j) => MatchPricing(
        searchCoins: (j['match_search_cost'] as num?)?.toInt() ?? kMatchFeeCoins,
        connectCoins:
            (j['match_connect_cost'] as num?)?.toInt() ?? kMatchConnectFeeCoins,
        freeSeconds:
            (j['match_free_seconds'] as num?)?.toInt() ?? kMatchFreeSeconds,
      );
}

final matchPricingProvider = FutureProvider<MatchPricing>((ref) async {
  try {
    return MatchPricing.fromJson(await PointsService().meteredPricing());
  } catch (_) {
    return const MatchPricing();
  }
});

/// Nilai siap pakai (fallback konstanta selama loading/error).
extension MatchPricingRead on WidgetRef {
  MatchPricing get matchPricing =>
      watch(matchPricingProvider).value ?? const MatchPricing();
}
