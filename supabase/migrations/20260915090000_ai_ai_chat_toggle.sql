-- ============================================================
-- TOGGLE AI↔AI CHAT (dummy AI bicara dengan dummy AI)
--
-- Sebelumnya AI↔AI SELALU boleh (blokir sender-dummy dihapus di
-- 20260912020000). Owner minta tombol on/off supaya uji coba Dhanu × Santi
-- bisa dimatikan tanpa mematikan Mode AI dummy (yang juga menyalakan
-- balasan ke user manusia).
--
-- Tombol: app_settings.ai_ai_chat_enabled (default TRUE = perilaku lama,
-- jadi tidak ada perubahan perilaku sampai admin mematikan).
--
-- Diterapkan di DUA lapis (defense in depth, kontrak sama):
--   1) trigger ai_reply_enqueue  → sender dummy & toggle off = tidak enqueue
--   2) edge ai-reply             → cermin gate (invoke langsung bypass trigger)
--
-- always_reply (expert/CS) TIDAK dikecualikan dari gate ini: kalau owner
-- mematikan AI↔AI, expert pun tidak balas pesan dari dummy lain. Itu memang
-- tujuan tombolnya. (Manusia → expert tetap selalu dibalas.)
--
-- menyentuh: ai_reply_enqueue
-- menyentuh: admin_ai_settings
-- ============================================================

-- ── 1. Kolom toggle (default true = perilaku lama) ──
alter table public.app_settings
  add column if not exists ai_ai_chat_enabled boolean not null default true;

-- ── 2. ai_reply_enqueue: gate AI↔AI ──
-- Salinan live 20260914060000_ai_reply_log_fix.sql + satu gate baru:
-- setelah cek v_sender_is_dummy, kalau toggle off → skip:dummy_sender_off.
create or replace function public.ai_reply_enqueue()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_other uuid;
  v_no_rate boolean;
  v_always_reply boolean;
  v_sender_no_rate boolean;
  v_sender_is_dummy boolean;
  v_global boolean;
  v_ai_ai_on boolean;
  v_max int;
  v_min int;
  v_gmax int;
  v_gmin int;
  v_dummy_out_1h int;
  v_last_dummy_out timestamptz;
  v_ai_ai_1h int;
begin
  -- Only plain text messages
  if coalesce(new.type, 'text') != 'text' then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:non_text', '{}');
    return new;
  end if;

  select x into v_other
  from unnest(
    (select pc.participants from public.private_chats pc where pc.chat_id = new.chat_id)
  ) as x
  where x <> new.sender_id
  limit 1;
  if v_other is null then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, null, false, 'enqueue', 'skipped:no_other', '{}');
    return new;
  end if;

  -- Recipient must be an AI-enabled dummy (ambil config sekalian).
  -- PENTING: pakai IF NOT FOUND (bukan cek null!) — kolom flag boleh null.
  select d.ai_no_rate_limit, d.ai_always_reply, d.ai_max_replies, d.ai_min_interval
    into v_no_rate, v_always_reply, v_max, v_min
  from public.dummy_accounts d
  where d.uid = v_other and d.ai_enabled = true;
  if not found then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:dummy_disabled', '{}');
    return new;
  end if;

  v_sender_is_dummy := exists (
    select 1 from public.dummy_accounts d where d.uid = new.sender_id
  );

  select s.ai_global_enabled, s.ai_max_replies_per_hour, s.ai_min_interval_sec,
         coalesce(s.ai_ai_chat_enabled, true)
    into v_global, v_gmax, v_gmin, v_ai_ai_on
  from public.app_settings s where s.id = 'global';
  if v_global is distinct from true then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:global_off', '{}');
    return new;
  end if;

  -- ── TOGGLE AI↔AI (baru): sender dummy & tombol off → dummy tidak dibalas. ──
  if v_sender_is_dummy and not coalesce(v_ai_ai_on, true) then
    perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:ai_ai_off', '{}');
    return new;
  end if;

  -- ── always_reply (expert/CS): LEWATI semua cap & rate. Pesan selalu enqueue.
  if coalesce(v_always_reply, false) then
    perform public.ai_reply_post(new.chat_id, new.id, new.sender_id, v_other, false);
    return new;
  end if;

  v_max := coalesce(v_max, v_gmax, 20);
  v_min := coalesce(v_min, v_gmin, 2);

  if v_sender_is_dummy then
    -- ── AI↔AI: rate limit dummy pengirim (hormati flag no_rate_limit-nya) ──
    -- (cap 40/jam gabungan DIHAPUS di 20260912020000; stop = Mode AI / toggle)
    null;
  else
    -- ── Sender manusia: rate limit lama (per dummy, hormati no_rate_limit) ──
    if not coalesce(v_no_rate, false) then
      select count(*) into v_dummy_out_1h
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other
        and m.created_at > now() - interval '1 hour';
      if v_dummy_out_1h >= v_max then
        -- Kuota habis: dummy turun ke idle (bukan online tapi bungkam).
        begin
          if exists (
            select 1 from information_schema.columns
            where table_schema = 'public' and table_name = 'profiles'
              and column_name = 'last_seen'
          ) then
            update public.profiles
               set status = 'idle', last_seen = now()
             where id = v_other and status = 'online';
          else
            update public.profiles
               set status = 'idle'
             where id = v_other and status = 'online';
          end if;
        exception when others then
          null;
        end;
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_max', jsonb_build_object('out_1h', v_dummy_out_1h, 'max', v_max));
        return new;
      end if;

      select max(m.created_at) into v_last_dummy_out
      from public.private_messages m
      where m.chat_id = new.chat_id
        and m.sender_id = v_other;
      if v_last_dummy_out is not null
         and v_last_dummy_out > now() - make_interval(secs => v_min) then
        perform public.ai_log_reply(new.chat_id, new.id, new.sender_id, v_other, false, 'enqueue', 'skipped:rate_min_interval', '{}');
        return new;
      end if;
    end if;
  end if;

  -- Enqueue via helper terpusat (auth header + URL dari config + log).
  perform public.ai_reply_post(
    new.chat_id, new.id, new.sender_id, v_other, false
  );

  return new;
end;
$$;

-- ── 3. admin_ai_settings: +p_ai_ai_enabled (10-param) ──
-- Drop versi 9-param dulu supaya tidak ada overload ambigu.
drop function if exists public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text);
create or replace function public.admin_ai_settings(
  p_global_enabled boolean default null,
  p_max_replies integer default null,
  p_min_interval integer default null,
  p_guard_enabled boolean default null,
  p_api_base text default null,
  p_api_key text default null,
  p_default_model text default null,
  p_stt_base text default null,
  p_stt_key text default null,
  p_ai_ai_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.app_settings;
  v_prov public.ai_provider_config;
begin
  if not public.is_admin_request() then
    raise exception 'Unauthorized';
  end if;
  insert into public.app_settings (id) values ('global')
  on conflict (id) do nothing;

  update public.app_settings
  set ai_global_enabled = coalesce(p_global_enabled, ai_global_enabled),
      ai_max_replies_per_hour = coalesce(p_max_replies, ai_max_replies_per_hour),
      ai_min_interval_sec = coalesce(p_min_interval, ai_min_interval_sec),
      ai_guard_enabled = coalesce(p_guard_enabled, ai_guard_enabled),
      ai_ai_chat_enabled = coalesce(p_ai_ai_enabled, ai_ai_chat_enabled),
      updated_at = now()
  where id = 'global'
  returning * into v_row;

  -- Hanya pastikan baris provider bila ada field provider yang ditulis.
  -- Tanpa ini, baris 'global' yang sengaja dihapus user bangkit lagi
  -- di setiap pembacaan (GET tanpa parameter).
  if p_api_base is not null
     or p_api_key is not null
     or p_default_model is not null
     or p_stt_base is not null
     or p_stt_key is not null then
    insert into public.ai_provider_config (id) values ('global')
    on conflict (id) do nothing;
  end if;

  update public.ai_provider_config
  set api_base = coalesce(p_api_base, api_base),
      api_key = coalesce(p_api_key, api_key),
      default_model = coalesce(p_default_model, default_model),
      stt_api_base = coalesce(p_stt_base, stt_api_base),
      stt_api_key = coalesce(p_stt_key, stt_api_key),
      updated_at = now()
  where id = 'global'
  returning * into v_prov;

  return jsonb_build_object(
    'ai_global_enabled', v_row.ai_global_enabled,
    'ai_max_replies_per_hour', v_row.ai_max_replies_per_hour,
    'ai_min_interval_sec', v_row.ai_min_interval_sec,
    'ai_guard_enabled', v_row.ai_guard_enabled,
    'ai_ai_chat_enabled', v_row.ai_ai_chat_enabled,
    'ai_api_base', v_prov.api_base,
    'ai_api_key', v_prov.api_key,
    'ai_default_model', v_prov.default_model,
    'ai_stt_base', v_prov.stt_api_base,
    'ai_stt_key', v_prov.stt_api_key
  );
end;
$$;
revoke execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.admin_ai_settings(boolean, integer, integer, boolean, text, text, text, text, text, boolean) to authenticated, service_role;
