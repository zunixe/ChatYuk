-- ============================================================
-- Private Room - All together 4 + list batch
-- - Dukung hingga 4 broadcaster simultan (ganti live_uid tunggal)
-- - Batch list untuk N+1 private rooms screen
-- ============================================================

-- ---------- 1) Tabel broadcaster aktif (max 4 per room) ----------
create table if not exists public.room_broadcasters (
  room_id    text not null references public.rooms(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
create index if not exists room_broadcasters_room_idx on public.room_broadcasters(room_id);

alter table public.room_broadcasters enable row level security;
drop policy if exists rbc_select_member on public.room_broadcasters;
create policy rbc_select_member on public.room_broadcasters for select using (
  exists (select 1 from public.room_members m where m.room_id = room_broadcasters.room_id and m.user_id = auth.uid())
);
drop policy if exists rbc_insert_member on public.room_broadcasters;
create policy rbc_insert_member on public.room_broadcasters for insert with check (
  exists (select 1 from public.room_members m where m.room_id = room_broadcasters.room_id and m.user_id = auth.uid())
);
drop policy if exists rbc_delete_own on public.room_broadcasters;
create policy rbc_delete_own on public.room_broadcasters for delete using (user_id = auth.uid());

alter publication supabase_realtime add table public.room_broadcasters;

-- ---------- 2) RPC start/stop dengan cap 4 ----------
create or replace function public.start_broadcast(p_room_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cnt int; role text;
begin
  role := public.fn_room_role(auth.uid(), p_room_id);
  if role is null then raise exception 'Not a member'; end if;
  select count(*) into cnt from public.room_broadcasters where room_id = p_room_id;
  if cnt >= 4 then raise exception 'Broadcast full (4/4)'; end if;
  insert into public.room_broadcasters(room_id, user_id) values (p_room_id, auth.uid())
    on conflict do nothing;
  -- jaga live_uid untuk kompatibilitas UI lama (set jika kosong)
  update public.rooms set live_uid = auth.uid(), live_started_at = now()
    where id = p_room_id and live_uid is null;
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.stop_broadcast_v2(p_room_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.room_broadcasters where room_id = p_room_id and user_id = auth.uid();
  -- jika yang stop adalah pemilik live_uid, kosongkan live_uid
  update public.rooms set live_uid = null, live_started_at = null
    where id = p_room_id and live_uid = auth.uid();
  -- jika masih ada broadcaster lain, promosikan satu jadi live_uid
  update public.rooms set live_uid = (
    select user_id from public.room_broadcasters where room_id = p_room_id order by started_at limit 1
  ), live_started_at = now()
  where id = p_room_id and live_uid is null
    and exists (select 1 from public.room_broadcasters where room_id = p_room_id);
end; $$;

-- ---------- 3) List batch private rooms milik user (ganti N+1) ----------
create or replace function public.list_my_private_rooms(p_uid uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
  from public.rooms r
  where r.is_private = true
    and exists (select 1 from public.room_members m where m.room_id = r.id and m.user_id = p_uid);
$$;

-- ---------- 4) Flag SFU di app_settings ----------
alter table public.app_settings add column if not exists room_media_backend text not null default 'mesh' check (room_media_backend in ('mesh','sfu'));
