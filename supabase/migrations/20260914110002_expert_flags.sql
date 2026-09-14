-- ============================================
-- ChatYuk: EXPERT FLAGS — selalu balas + teks panjang
-- ============================================
-- Latar (koreksi owner):
--   * Admin Chatyuk = CS/ekspert: WAJIB selalu dibalas (ai_always_reply).
--     Di DB masih false, padahal persona-nya "CS resmi ... selalu solutif".
--   * HardwareExpert = ekspert teknis: jawabannya panjang terstruktur,
--     sejajar SoftwareExpert yang sudah long_answers=true. Di DB masih null.
--
-- Perubahan:
--   1) dummy_accounts.ai_always_reply = true  (Admin Chatyuk)
--   2) ai_persona || '{"long_answers": true}' (HardwareExpert; merge —
--      diagrams/tone/personality/extra_prompt TIDAK terhapus)
--
-- Idempoten: aman dijalankan ulang.
-- ============================================

-- 1) Admin Chatyuk: selalu dibalas.
update public.dummy_accounts
   set ai_always_reply = true
 where lower(nickname) = lower('Admin Chatyuk')
   and ai_always_reply is distinct from true;

-- 2) HardwareExpert: teks panjang (merge ke persona lama).
update public.dummy_accounts
   set ai_persona = coalesce(ai_persona, '{}'::jsonb) || '{"long_answers": true}'::jsonb
 where lower(nickname) = lower('HardwareExpert')
   and coalesce(ai_persona ->> 'long_answers', '') <> 'true';
