-- Expose potongan platform gift ke klien (`gift_cut_pct`).
--
-- Latar: penerima gift mendapat NETTO (harga - cut) ke bucket `earned`.
-- Sebelum ini klien tidak tahu cut-nya, jadi bubble "Menerima hadiah" hanya
-- menampilkan nama gift tanpa info koin yang benar-benar didapat penerima.
-- Dengan `gift_cut_pct` di `metered_pricing_public`, klien bisa menampilkan
-- "+N 🪙" yang persis sama dengan kredit server (rumus: n - (n*cut)/100).
--
-- Sifat: additive (satu key baru di JSON output). Tidak mengubah nilai lain.

CREATE OR REPLACE FUNCTION public.metered_pricing_public()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return (select jsonb_build_object(
    'call_audio_cost_per_min', call_audio_cost_per_min,
    'call_video_cost_per_min', call_video_cost_per_min,
    'call_free_minutes_daily', call_free_minutes_daily,
    'filter_gender_cost', filter_gender_cost,
    'nearby_cost', nearby_cost,
    -- == v_fee di random_match_join (fee pencarian saat pasangan terbentuk).
    'match_search_cost', 2,
    'match_connect_cost',
      coalesce((metered_pricing->'match_call'->>'unit_cost')::int, 10),
    'match_free_seconds', 30,
    'photo_unlock_cost', photo_unlock_perm,
    -- Potongan platform gift — penerima mendapat (harga - cut).
    'gift_cut_pct', coalesce(gift_cut_pct, 30)
  ) from app_settings where id = 'global');
end; $function$
