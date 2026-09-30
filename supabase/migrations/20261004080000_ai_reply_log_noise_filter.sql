-- ============================================================
-- FILTER NOISE di penulis log `ai_reply_log`.
--
-- LATAR (audit 2026-10-04, lihat riwayat terakhir):
--   Tabel `ai_reply_log` (retensi 7 hari, cron chatyuk-ai-log-cleanup)
--   mentok ~11k baris / ~7 MB, TAPI dari seluruh isi hanya ~39 baris
--   `replied` per 7 hari. Artinya >99% baris adalah log "skipped" gate,
--   dan 84% di antaranya DUA decision yang tidak informatif:
--     - `skipped:dummy_disabled` (path SQL/enqueue)  ~5401 baris
--     - `skipped:ai_disabled`    (path edge)          ~4195 baris
--   Keduanya = "dummy penerima sedang AI-off" — sinyalnya sudah tersedia
--   langsung di `dummy_accounts.ai_enabled`; mencatatnya tiap pesan hanya
--   membanjiri log observability sehingga kasus menarik (replied / error /
--   skip gate lain) tenggelam.
--
-- YANG DIBUAT:
--   `ai_log_reply()` menolak menulis 2 decision di atas (denylist
--   deterministik, bukan sampling). Semua call-site SQL (dalam
--   ai_reply_enqueue / ai_reply_post yang FROZEN) otomatis ikut terfilter
--   karena melewati helper pusat ini — TANPA menyentuh fungsi FROZEN.
--   Jalur edge (`supabase/functions/ai-reply`) memakai filter setara di
--   shadow `json()` (deploy terpisah).
--
-- CATATAN: fungsi ini TIDAK frozen (lihat scripts/frozen_functions.txt),
--   dan signature tidak berubah → tidak butuh snapshot refresh.
--
-- CARA APPLY: Management API (lihat supabase/migrations/APPLIED_VIA_API.md),
--   satu statement per request.
-- ============================================================

create or replace function public.ai_log_reply(
  p_chat_id text,
  p_trigger_msg_id bigint,
  p_sender_id uuid,
  p_dummy_uid uuid,
  p_proactive boolean,
  p_stage text,
  p_decision text,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Noise filter: dua gate ini tidak lagi dicatat (sinyalnya ada di
  -- dummy_accounts.ai_enabled). Semua decision lain tetap tercatat.
  if p_decision in ('skipped:dummy_disabled', 'skipped:ai_disabled') then
    return;
  end if;

  insert into public.ai_reply_log(chat_id, trigger_msg_id, sender_id, dummy_uid, proactive, stage, decision, detail)
  values (p_chat_id, p_trigger_msg_id, p_sender_id, p_dummy_uid, coalesce(p_proactive, false), p_stage, p_decision, coalesce(p_detail, '{}'::jsonb));
exception when others then
  null;
end;
$$;

revoke execute on function public.ai_log_reply(text, bigint, uuid, uuid, boolean, text, text, jsonb) from public, anon;
grant execute on function public.ai_log_reply(text, bigint, uuid, uuid, boolean, text, text, jsonb) to authenticated, service_role;

-- Verifikasi setelah apply:
--   1) Definisi memuat filter:
--        select prosrc from pg_proc where proname='ai_log_reply';
--   2) Uji negatif (tidak bertambah):
--        select public.ai_log_reply('x',null,null,null,false,'enqueue','skipped:dummy_disabled','{}');
--   3) Uji positif (bertambah):
--        select public.ai_log_reply('x',null,null,null,false,'enqueue','skipped:rate_max','{}');
