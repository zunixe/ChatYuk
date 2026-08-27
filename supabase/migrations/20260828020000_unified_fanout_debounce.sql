-- Unified fan-out debounce untuk semua notifikasi 1→N
-- online (10m), timeline post (0), timeline count (5s), room (3s)

alter table public.profiles add column if not exists last_online_notified_at timestamptz;
alter table public.posts add column if not exists last_notified_at timestamptz;
alter table public.rooms add column if not exists last_notified_at timestamptz;

-- Fanout online: hanya transisi offline→online + debounce 10m → HTTP ke fanout
create or replace function public.notify_online_fanout()
returns trigger language plpgsql security definer set search_path = public as $$
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
end; $$;

drop trigger if exists profiles_online_fanout_trigger on public.profiles;
create trigger profiles_online_fanout_trigger
  after update of status on public.profiles
  for each row execute function public.notify_online_fanout();

-- Fanout timeline post baru: langsung HTTP tanpa debounce
create or replace function public.notify_timeline_post_fanout()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','timeline','id', new.id::text)
  );
  return new;
end; $$;

drop trigger if exists posts_timeline_fanout_trigger on public.posts;
create trigger posts_timeline_fanout_trigger
  after insert on public.posts
  for each row execute function public.notify_timeline_post_fanout();

-- Fanout timeline count update: debounce 5s per post
create or replace function public.notify_timeline_count_fanout()
returns trigger language plpgsql security definer set search_path = public as $$
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
end; $$;

drop trigger if exists posts_count_fanout_trigger on public.posts;
create trigger posts_count_fanout_trigger
  after update of like_count, comment_count, share_count on public.posts
  for each row execute function public.notify_timeline_count_fanout();

-- Fanout room: debounce 3s per room via presence, trigger on room_presence insert
-- (room_presence sudah Presence, jadi tidak perlu DB trigger tambahan)
-- Cukup pg_notify untuk private room creation
create or replace function public.notify_room_fanout()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://fohcucyyejdryryoxitm.supabase.co/functions/v1/fanout',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('type','room','id', new.id::text)
  );
  return new;
end; $$;

drop trigger if exists rooms_fanout_trigger on public.rooms;
create trigger rooms_fanout_trigger
  after insert on public.rooms
  for each row execute function public.notify_room_fanout();
