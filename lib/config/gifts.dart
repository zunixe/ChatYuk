/// Katalog gift lokal — cermin dari tabel gift_catalog di server.
/// Dipakai untuk render bubble & picker tanpa harus fetch tiap kali.
/// Sinkron dengan seed di migration 20260814250000_gift_platform_cut_phase3.sql
class GiftItem {
  final String id;
  final String emoji;
  final String nameId;
  final String nameEn;
  final int coins;
  const GiftItem(this.id, this.emoji, this.nameId, this.nameEn, this.coins);
}

const List<GiftItem> kGiftCatalog = [
  GiftItem('rose', '🌹', 'Mawar', 'Rose', 10),
  GiftItem('coffee', '☕', 'Kopi', 'Coffee', 25),
  GiftItem('teddy', '🧸', 'Boneka', 'Teddy Bear', 50),
  GiftItem('cake', '🎂', 'Kue', 'Cake', 75),
  GiftItem('diamond', '💎', 'Berlian', 'Diamond', 150),
  GiftItem('crown', '👑', 'Mahkota', 'Crown', 300),
  GiftItem('rocket', '🚀', 'Roket', 'Rocket', 500),
  GiftItem('sportscar', '🏎️', 'Mobil Sport', 'Sports Car', 1000),
];

GiftItem? giftById(String id) {
  for (final g in kGiftCatalog) {
    if (g.id == id) return g;
  }
  return null;
}

/// Biaya pencarian match (YukCoin) — dipotong SEKALI saat pasangan terbentuk,
/// bukan saat tombol Match diklik. HARUS sama dengan `v_fee` di
/// `random_match_join` (supabase/migrations/20261031110014_match_charge_on_pair.sql);
/// server tetap sumber kebenaran, ini hanya untuk tampilan.
const int kMatchFeeCoins = 2;

/// Menit gratis pertama untuk match video (server: 20261031110011 —
/// `c.kind = 'random'` → menit ke-1 gratis). Hanya untuk tampilan.
const int kMatchFreeMinutes = 1;
