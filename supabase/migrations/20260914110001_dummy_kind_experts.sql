-- ============================================
-- ChatYuk: DUMMY KIND — koreksi set EXPERT
-- ============================================
-- menyentuh: admin_list_dummies
-- (tidak mengubah fungsi; trigger guard karena nama fn disebut di komentar.
--  FROZEN function TIDAK di-replace di migration ini.)
--
-- Latar:
--   20260914110000_dummy_kind.sql menandai expert HANYA dari nickname
--   ('softwareexpert','hardwareexpert'). Koreksi owner: expert = akun
--   dengan ciri "online 24 jam + teks panjang" — mencakup Admin Chatyuk
--   (ai_always_online + long_answers) dan CS teknis (Dr Nara, Kang Modal:
--   ai_always_reply + long_answers), bukan cuma 2 yang namanya Expert.
--
-- Definisi EXPERT yang dipakai (konsisten & terukur):
--   ai_always_online = true  ATAU  ai_always_reply = true  ATAU
--   (ai_persona->>'long_answers') = 'true'
-- ── 7 akun sisanya (agoy/aqila/BinorMuda/Dhanu/MbakSari/Sarah/Venty)
--    punya KETIGANYA false/null → tetap regular.
--
-- Kolom `kind` sendiri dari 20260914110000 (sudah ada). Migration ini
-- hanya memperbaiki DATA (idempoten).
-- ============================================

-- 1) Naikkan ke expert: semua yang punya ciri expert.
update public.dummy_accounts
   set kind = 'expert'
 where kind <> 'expert'
   and (
     coalesce(ai_always_online, false)
     or coalesce(ai_always_reply, false)
     or (ai_persona ->> 'long_answers') = 'true'
   );

-- 2) Turunkan ke regular: yang tidak punya ciri expert sama sekali.
--    (Menjaga bila di masa depan ada baris expert tanpa ciri.)
update public.dummy_accounts
   set kind = 'regular'
 where kind <> 'regular'
   and not coalesce(ai_always_online, false)
   and not coalesce(ai_always_reply, false)
   and coalesce(ai_persona ->> 'long_answers', '') <> 'true';

-- Verifikasi cepat (komentar, bukan query — apply via API tak balas row):
--   select nickname, kind from public.dummy_accounts order by kind, nickname;
--   Harapan: expert = Admin Chatyuk, Dr Nara, HardwareExpert, Kang Modal, SoftwareExpert.
