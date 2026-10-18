-- POLLING di GRUP & GLOBAL ROOM (ala WhatsApp) — paritas dengan private chat
-- (lihat 20261018130000_chat_poll.sql).
--
-- ADITIF (tidak mengubah fungsi FROZEN):
--  1) type 'poll' di messages_type_check (basis = constraint LIVE, jadi tipe
--     yang sudah ada TIDAK hilang).
--  2) Kolom messages.poll jsonb = definisi poll
--       {"q": "pertanyaan", "o": ["opsi1", ...], "m": false}
--     Disimpan DI BARIS PESAN supaya bubble tampil lengkap dari cache lokal di
--     frame pertama. text pesan = '📊 <pertanyaan>' → notif & last_message rapi
--     lewat cabang teks yang sudah ada (fungsi notif tak disentuh).
--  3) Tabel room_poll_votes (suara), RLS baca = aturan SAMA dengan
--     messages_select (room publik: siapa saja; room privat: anggota; admin:
--     selalu). Tulis HANYA lewat RPC vote_room_poll (security definer).
--  4) RPC vote_room_poll + get_room_poll_results (batch, lazy load bubble).

-- 1) Tipe pesan (basis: constraint LIVE messages_type_check)
alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check check (
  type = any (array[
    'text','image','view_once','view_once_expired','voice','coin','gift','call',
    'video','video_once','video_once_expired','location','sticker','file','poll'
  ])
);

-- 2) Definisi poll di baris pesan
alter table public.messages add column if not exists poll jsonb;

-- 3) Suara poll room
create table if not exists public.room_poll_votes (
  message_id bigint not null
    references public.messages(id) on delete cascade,
  room_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_idx smallint not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, option_idx)
);
create index if not exists room_poll_votes_room_idx
  on public.room_poll_votes (room_id);

alter table public.room_poll_votes enable row level security;
alter table public.room_poll_votes replica identity full;

drop policy if exists room_poll_votes_select_reader on public.room_poll_votes; -- SAFE: tabel BARU khusus poll room; fitur terdampak: poll room saja
create policy room_poll_votes_select_reader on public.room_poll_votes -- SAFE: tabel BARU; hanya pembaca room (publik/anggota/admin) yang boleh lihat suara; fitur: poll room saja
  for select to authenticated
  using (
    (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
    or not exists (
      select 1 from public.rooms r
      where r.id = room_poll_votes.room_id and r.is_private = true
    )
    or exists (
      select 1 from public.room_members m
      where m.room_id = room_poll_votes.room_id
        and m.user_id = auth.uid()
    )
  );

revoke insert, update, delete on public.room_poll_votes from anon, authenticated; -- SAFE: tabel BARU; tulis hanya via RPC vote_room_poll; fitur: poll room saja

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'room_poll_votes'
  ) then
    alter publication supabase_realtime add table public.room_poll_votes;
  end if;
end $$;

-- 4a) Hasil poll room (batch): counts per opsi, pilihan saya, jumlah pemilih.
create or replace function public.get_room_poll_results(p_message_ids bigint[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'counts', (
      select coalesce(jsonb_agg(coalesce(c.n, 0) order by g.i), '[]'::jsonb)
      from generate_series(0, jsonb_array_length(m.poll->'o') - 1) as g(i)
      left join (
        select v.option_idx, count(*)::int as n
        from public.room_poll_votes v
        where v.message_id = m.id
        group by v.option_idx
      ) c on c.option_idx = g.i
    ),
    'mine', (
      select coalesce(jsonb_agg(v.option_idx order by v.option_idx), '[]'::jsonb)
      from public.room_poll_votes v
      where v.message_id = m.id and v.user_id = auth.uid()
    ),
    'voters', (
      select count(distinct v.user_id)::int
      from public.room_poll_votes v where v.message_id = m.id
    )
  )), '[]'::jsonb)
  from public.messages m
  where m.id = any (p_message_ids)
    and m.type = 'poll'
    and m.poll is not null
    and (
      (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
      or not exists (
        select 1 from public.rooms r
        where r.id = m.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members mm
        where mm.room_id = m.room_id and mm.user_id = auth.uid()
      )
    );
$$;

-- 4b) Vote: GANTI pilihan saya untuk poll room ini (kosong = tarik suara).
create or replace function public.vote_room_poll(
  p_message_id bigint,
  p_options int[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room text;
  v_poll jsonb;
  v_n int;
  v_opts int[] := coalesce(p_options, '{}');
  v_i int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select m.room_id, m.poll into v_room, v_poll
  from public.messages m
  where m.id = p_message_id
    and m.type = 'poll'
    and coalesce(m.is_deleted, false) = false
    and (
      (auth.jwt() ->> 'email') = 'zunixe@gmail.com'
      or not exists (
        select 1 from public.rooms r
        where r.id = m.room_id and r.is_private = true
      )
      or exists (
        select 1 from public.room_members mm
        where mm.room_id = m.room_id and mm.user_id = auth.uid()
      )
    );
  if v_room is null or v_poll is null then
    raise exception 'poll not found';
  end if;

  v_n := jsonb_array_length(v_poll->'o');
  select coalesce(array_agg(distinct x order by x), '{}') into v_opts
  from unnest(v_opts) as x;
  foreach v_i in array v_opts loop
    if v_i < 0 or v_i >= v_n then
      raise exception 'invalid option';
    end if;
  end loop;
  if coalesce((v_poll->>'m')::boolean, false) = false
     and cardinality(v_opts) > 1 then
    raise exception 'single choice poll';
  end if;

  delete from public.room_poll_votes
  where message_id = p_message_id and user_id = auth.uid();

  insert into public.room_poll_votes (message_id, room_id, user_id, option_idx)
  select p_message_id, v_room, auth.uid(), x from unnest(v_opts) as x;

  return coalesce(
    public.get_room_poll_results(array[p_message_id]) -> 0,
    '{}'::jsonb
  );
end;
$$;

revoke execute on function public.get_room_poll_results(bigint[]) from anon;
revoke execute on function public.vote_room_poll(bigint, int[]) from anon;
grant execute on function public.get_room_poll_results(bigint[]) to authenticated;
grant execute on function public.vote_room_poll(bigint, int[]) to authenticated;
