-- ============================================================
-- Langkah 2: call_push (2 overload) + notify_call_ended → OUTBOX
--
-- menyentuh: call_push
-- menyentuh: notify_call_ended
--
-- Mengganti `perform net.http_post(...)` → `insert into public.outbox`.
-- Logika lain 100% IDENTIK (payload, dedup, dst). Token sudah via
-- user_fcm_tokens (Langkah 1). Dasar = definisi LIVE terbaru.
--
-- call_push 5-arg tetap ada (dipakai klien/trigger lama), keduanya ke outbox.
-- notify_call_ended tetap set new.notif_sent_at (idempoten).
--
-- PENTING: cron outbox-worker WAJIB aktif. Snapshot DI-REGEN setelah apply.
-- ROLLBACK: re-apply definisi sebelumnya (20260913130001 / 20260828030000).
-- ============================================================

-- ── call_push (5-arg) → outbox ──────────────────────────────────────────────
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text, p_call_type text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  rec record;
  v_chat_id text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  -- fan-out ke semua token aktif (user_devices + fallback profiles)
  for rec in select public.user_fcm_tokens(p_callee) as fcm_token loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', rec.fcm_token,
      'title', p_name,
      'body', p_call_type,
      'data', jsonb_build_object(
        'type', 'call',
        'callId', p_call,
        'callerUid', p_caller,
        'fromName', p_name,
        'otherName', p_name,
        'callType', p_call_type,
        'chatId', v_chat_id
      )
    ));
  end loop;
end;
$function$;

-- ── call_push (6-arg) → outbox ──────────────────────────────────────────────
create or replace function public.call_push(
  p_callee uuid, p_call uuid, p_caller uuid, p_caller_name text,
  p_call_type text, p_avatar text default ''
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  t text;
  p_name text := coalesce(nullif(p_caller_name,''), 'User');
  v_chat_id text;
  v_msg text;
begin
  v_chat_id := least(p_caller::text, p_callee::text) || '_' || greatest(p_caller::text, p_callee::text);
  v_msg := case when p_call_type = 'video' then 'Panggilan video' else 'Panggilan suara' end;
  for t in select public.user_fcm_tokens(p_callee) loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', t,
      'title', p_name,
      'body', v_msg,
      'data', jsonb_build_object(
        'type', 'call',
        'toUid', p_callee,
        'callId', p_call,
        'callerUid', p_caller,
        'fromName', p_name,
        'otherName', p_name,
        'callType', p_call_type,
        'chatId', v_chat_id,
        'avatarUrl', coalesce(p_avatar,''),
        'message', v_msg
      )
    ));
  end loop;
end; $function$;

-- ── notify_call_ended → outbox ──────────────────────────────────────────────
create or replace function public.notify_call_ended()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  rec record;
  v_chat_id text;
  v_name text;
  v_body text;
begin
  -- Hanya transisi pertama dari ringing/answered ke terminal
  if old.status not in ('ringing','answered') then return new; end if;
  if new.status not in ('canceled','missed','declined','ended','busy') then return new; end if;
  -- Idempoten: jika sudah pernah kirim untuk call ini, jangan kirim lagi
  if new.notif_sent_at is not null then return new; end if;

  v_chat_id := least(new.caller_id::text, new.callee_id::text) || '_' || greatest(new.caller_id::text, new.callee_id::text);
  select nickname into v_name from public.profiles where id = new.caller_id;
  v_name := coalesce(nullif(v_name,''), 'User');
  v_body := case
    when new.status in ('ended','canceled') then 'Call ended'
    when new.status = 'missed' then 'Missed call'
    when new.status = 'declined' then 'Call declined'
    when new.status = 'busy' then 'Busy'
    else 'Call ended'
  end;

  for rec in select public.user_fcm_tokens(new.callee_id) as fcm_token loop
    insert into public.outbox (type, payload)
    values ('push', jsonb_build_object(
      'token', rec.fcm_token,
      'title', v_name,
      'body', v_body,
      'data', jsonb_build_object(
        'type', 'call_ended',
        'toUid', new.callee_id,
        'callId', new.id,
        'chatId', v_chat_id,
        'callerUid', new.caller_id,
        'otherName', v_name
      )
    ));
  end loop;

  -- Tandai sudah dikirim supaya update berikutnya tidak kirim lagi
  new.notif_sent_at := now();
  return new;
exception when others then return new;
end; $function$;

-- Verifikasi:
--   select proname, pg_get_function_identity_arguments(oid), (prosrc like '%outbox%') ob, (prosrc like '%http_post%') hp from pg_proc where proname in ('call_push','notify_call_ended');
