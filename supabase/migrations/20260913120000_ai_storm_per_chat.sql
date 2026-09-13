-- Ngambek (storm) per-chat: marah ke satu orang tidak membungkam chat lain.
-- ai_chat_state.storm_until = diam tidak membalas HANYA chat ini sampai waktu
-- tsb; status online dipertahankan sehingga chat lain tetap dibalas normal.
-- Flag global dummy_accounts.ai_offline_until tetap ada sebagai fallback
-- (cek ngambek menghormati keduanya), tapi penulis baru hanya memakai
-- storm_until per-chat.
alter table public.ai_chat_state
  add column if not exists storm_until timestamptz;
