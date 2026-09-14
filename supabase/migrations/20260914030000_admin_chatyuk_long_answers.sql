-- Admin Chatyuk = customer service: jawaban boleh panjang & terstruktur.
-- Tanpa flag long_answers, ai-reply memakai ATURAN PANJANG guard ON
-- (2-12 kata, SATU kalimat) + sanitize cap 90 char → keluhan "balasan
-- sedikit-sedikit kayak terbatas". Dengan flag ini: max_tokens 1000,
-- cap 3000 char keepLines, maks 24 baris, format bernomor rapi.
-- Pola merge || supaya personality/tone/extra_prompt lama tidak hilang
-- (sama seperti fix expert di APPLIED_VIA_API 2026-09-13).
update public.dummy_accounts d
   set ai_persona = coalesce(d.ai_persona, '{}'::jsonb) || '{"long_answers": true}'::jsonb
  from public.profiles p
 where p.id = d.uid
   and p.nickname ilike '%admin%chatyuk%';
