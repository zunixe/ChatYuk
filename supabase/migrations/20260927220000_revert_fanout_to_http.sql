-- ============================================================
-- Outbox Fase E (revisi): REVERT 4 fanout topical ke net.http_post
--
-- Alasan: edge `fanout` mengautentikasi via service_role JWT
-- (`isServiceRoleJwt`), sedangkan worker outbox memakai fetch dengan
-- SUPABASE_SERVICE_ROLE_KEY yang formatnya tidak dijamin JWT di runtime
-- (uji: worker→fanout gagal, sedangkan worker→send-push OK karena
-- send-push terima x-app-secret). Daripada berisiko mematikan fanout
-- topical (online/room/timeline → notif realtime), kita KEMBALIKAN
-- ke perilaku asli `net.http_post` (yang sudah terbukti & live sejak lama).
--
-- Yang TETAP via outbox (aman, terverifikasi): notify_contact_online &
-- notify_broadcast_started (pakai send-push + x-app-secret).
--
-- Dasar = definisi live sebelum 20260927210000 (net.http_post).
-- ============================================================

-- ── notify_online_fanout (asli) ─────────────────────────────────────────────
create or replace function public.notify_online_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status = 'online' and coalesce(old.status,'offline') != 'online' then
    if new.last_online_notified_at is null or now() - new.last_online_notified_at > interval '10 minutes' then
      perform net.http_post(
        url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('type','online','id', new.id::text)
      );
      update public.profiles set last_online_notified_at = now() where id = new.id;
    end if;
  end if;
  return new;
end; $function$;

-- ── notify_room_fanout (asli) ───────────────────────────────────────────────
create or replace function public.notify_room_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','room','id', new.id::text)
  );
  return new;
end; $function$;

-- ── notify_timeline_post_fanout (asli) ──────────────────────────────────────
create or replace function public.notify_timeline_post_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','timeline','id', new.id::text)
  );
  return new;
end; $function$;

-- ── notify_timeline_count_fanout (asli) ─────────────────────────────────────
create or replace function public.notify_timeline_count_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if coalesce(new.like_count,0) = coalesce(old.like_count,0)
     and coalesce(new.comment_count,0) = coalesce(old.comment_count,0)
     and coalesce(new.share_count,0) = coalesce(old.share_count,0) then
    return new;
  end if;
  if new.last_notified_at is null or now() - new.last_notified_at > interval '5 seconds' then
    perform net.http_post(
      url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('type','timeline', 'id', new.id::text)
    );
    update public.posts set last_notified_at = now() where id = new.id;
  end if;
  return new;
end; $function$;

-- Verifikasi:
--   select proname, (prosrc like '%http_post%') hp, (prosrc like '%outbox%') ob
--     from pg_proc where proname like 'notify_%fanout';
--   → hp=true, ob=false.
