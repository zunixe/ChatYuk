-- Fase 1 per-country shard (tetap Supabase) — 1M DAU per country
-- - GIN untuk chat list (K1), country indexes, RPC per-country, cleanup room_presence

-- 1) GIN participants untuk private_chats.contains / RLS any(participants)
create index if not exists idx_private_chats_participants_gin on public.private_chats using gin (participants);

-- 2) Country indexes (per-region shard)
create index if not exists idx_profiles_country_last_seen on public.profiles (country, last_seen desc) where status in ('online','idle');
-- posts belum punya country -> tambah kolom + backfill + trigger auto-fill
alter table public.posts add column if not exists country text not null default '';
create index if not exists idx_posts_country_boost_created on public.posts (country, is_boosted desc, created_at desc);
-- backfill country dari profiles.author_id (sekali)
update public.posts p set country = coalesce(pr.country, '') from public.profiles pr where pr.id = p.author_id and (p.country = '' or p.country is null);
-- trigger isi country otomatis saat insert posts
create or replace function public.posts_fill_country() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if coalesce(new.country,'') = '' then
    select coalesce(country,'') into new.country from public.profiles where id = new.author_id;
  end if;
  return new;
end; $$;
drop trigger if exists posts_fill_country_trigger on public.posts;
create trigger posts_fill_country_trigger before insert on public.posts for each row execute function public.posts_fill_country();
-- profiles.country mungkin text '' untuk anon; index tetap selektif untuk registered

-- 3) RPC get_online_users per-country (shard per country, bukan global)
create or replace function public.get_online_users(p_country text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rows jsonb;
begin
  p_limit := least(greatest(coalesce(p_limit,100),1), 1000);
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'nickname', s.nickname, 'gender', s.gender, 'age', s.age,
    'country', s.country, 'city', s.city, 'status', s.status, 'avatar', s.avatar,
    'is_registered', s.is_registered, 'last_seen', s.last_seen
  ) order by s.last_seen desc), '[]'::jsonb) into rows
  from (
    select id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen
    from public.profiles
    where status in ('online','idle')
      and last_seen >= now() - interval '30 minutes'
      and (p_country is null or country = p_country)
    order by last_seen desc
    limit p_limit
  ) s;
  return rows;
end; $$;
grant execute on function public.get_online_users(text,int) to authenticated, anon;
-- keep old signature for backward compat (p_limit only) — wrapper
create or replace function public.get_online_users(p_limit int default 100)
returns jsonb language sql security definer set search_path = public as $$
  select public.get_online_users(null::text, p_limit);
$$;
grant execute on function public.get_online_users(int) to authenticated, anon;

-- 4) RPC count room presence per-country (ganti global stream chat_service:1626)
create or replace function public.count_room_presence_by_country(p_country text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rows jsonb;
begin
  if p_country is not null and btrim(p_country) = '' then p_country := null; end if;
  select coalesce(jsonb_object_agg(r.room_id, r.cnt), '{}'::jsonb) into rows
  from (
    select rp.room_id, count(*)::int as cnt
    from public.room_presence rp
    join public.profiles pr on pr.id = rp.user_id
    where rp.joined_at > now() - interval '10 minutes'
      and (p_country is null or pr.country = p_country)
    group by rp.room_id
  ) r;
  return coalesce(rows, '{}'::jsonb);
end; $$;
grant execute on function public.count_room_presence_by_country(text) to authenticated, anon;

-- 5) Cleanup room_presence stale (jalan tiap menit via cron atau dipanggil app; idempotent)
create or replace function public.cleanup_room_presence(p_minutes int default 10)
returns int language plpgsql security definer set search_path = public as $$
declare deleted int;
begin
  p_minutes := least(greatest(coalesce(p_minutes,10),1), 60);
  delete from public.room_presence where joined_at < now() - (p_minutes || ' minutes')::interval;
  get diagnostics deleted = row_count;
  return deleted;
end; $$;
grant execute on function public.cleanup_room_presence(int) to authenticated, service_role;

-- 6) Ensure timeline index per-country already exists via (2); list_posts will be patched next to accept p_country
