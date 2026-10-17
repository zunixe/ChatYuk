-- POLLING di private chat (ala WhatsApp).
--
-- ADITIF (tidak mengubah fungsi FROZEN / policy tabel bersama):
--  1) type 'poll' di private_messages_type_check (basis = constraint live).
--  2) Kolom private_messages.poll jsonb = definisi poll
--       {"q": "pertanyaan", "o": ["opsi1", ...], "m": false}
--     Disimpan DI BARIS PESAN supaya bubble tampil lengkap dari cache lokal
--     di frame pertama (tanpa fetch → tanpa lompatan layout).
--     text pesan = '📊 <pertanyaan>' → notif & last_message rapi lewat
--     cabang `else new.text` yang sudah ada (fungsi notif tak disentuh).
--  3) Tabel chat_poll_votes (suara), RLS: hanya peserta chat yang bisa BACA;
--     tulis HANYA lewat RPC vote_poll (security definer, tervalidasi).
--  4) RPC vote_poll + get_poll_results (batch, untuk lazy load bubble).

-- 1) Tipe pesan
alter table public.private_messages
  drop constraint if exists private_messages_type_check;
alter table public.private_messages
  add constraint private_messages_type_check check (
    type = any (array[
      'text','image','view_once','view_once_expired','voice','coin','gift',
      'call','video','video_once','video_once_expired','location','sticker',
      'file','poll'
    ])
  );

-- 2) Definisi poll di baris pesan
alter table public.private_messages add column if not exists poll jsonb;

-- 3) Suara
create table if not exists public.chat_poll_votes (
  message_id bigint not null
    references public.private_messages(id) on delete cascade,
  chat_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_idx smallint not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, option_idx)
);
create index if not exists chat_poll_votes_chat_idx
  on public.chat_poll_votes (chat_id);

alter table public.chat_poll_votes enable row level security;
alter table public.chat_poll_votes replica identity full;

drop policy if exists chat_poll_votes_select_participant on public.chat_poll_votes; -- SAFE: tabel BARU khusus poll; fitur terdampak: poll saja
create policy chat_poll_votes_select_participant on public.chat_poll_votes -- SAFE: tabel BARU; hanya peserta chat boleh baca suara; fitur: poll saja
  for select to authenticated
  using (exists (
    select 1 from public.private_chats pc
    where pc.chat_id = chat_poll_votes.chat_id
      and auth.uid() = any (pc.participants)
  ));

-- Tulis hanya lewat RPC (tabel BARU khusus poll, bukan tabel bersama).
revoke insert, update, delete on public.chat_poll_votes from anon, authenticated; -- SAFE: tabel BARU; tulis hanya via RPC vote_poll; fitur: poll saja

-- Realtime suara (dipakai layar chat yang terbuka, filter chat_id).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'chat_poll_votes'
  ) then
    alter publication supabase_realtime add table public.chat_poll_votes;
  end if;
end $$;

-- 4a) Hasil poll (batch): counts per opsi, pilihan saya, jumlah pemilih.
create or replace function public.get_poll_results(p_message_ids bigint[])
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
        from public.chat_poll_votes v
        where v.message_id = m.id
        group by v.option_idx
      ) c on c.option_idx = g.i
    ),
    'mine', (
      select coalesce(jsonb_agg(v.option_idx order by v.option_idx), '[]'::jsonb)
      from public.chat_poll_votes v
      where v.message_id = m.id and v.user_id = auth.uid()
    ),
    'voters', (
      select count(distinct v.user_id)::int
      from public.chat_poll_votes v where v.message_id = m.id
    )
  )), '[]'::jsonb)
  from public.private_messages m
  join public.private_chats pc on pc.chat_id = m.chat_id
  where m.id = any (p_message_ids)
    and m.type = 'poll'
    and m.poll is not null
    and auth.uid() = any (pc.participants);
$$;

-- 4b) Vote: GANTI pilihan saya untuk poll ini (kosong = tarik suara).
create or replace function public.vote_poll(p_message_id bigint, p_options int[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chat text;
  v_poll jsonb;
  v_n int;
  v_opts int[] := coalesce(p_options, '{}');
  v_i int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select m.chat_id, m.poll into v_chat, v_poll
  from public.private_messages m
  join public.private_chats pc on pc.chat_id = m.chat_id
  where m.id = p_message_id
    and m.type = 'poll'
    and coalesce(m.is_deleted, false) = false
    and auth.uid() = any (pc.participants);
  if v_chat is null or v_poll is null then
    raise exception 'poll not found';
  end if;

  v_n := jsonb_array_length(v_poll->'o');
  -- Unik + dalam rentang.
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

  delete from public.chat_poll_votes
  where message_id = p_message_id and user_id = auth.uid();

  insert into public.chat_poll_votes (message_id, chat_id, user_id, option_idx)
  select p_message_id, v_chat, auth.uid(), x from unnest(v_opts) as x;

  return coalesce(public.get_poll_results(array[p_message_id]) -> 0, '{}'::jsonb);
end;
$$;

revoke execute on function public.get_poll_results(bigint[]) from anon;
revoke execute on function public.vote_poll(bigint, int[]) from anon;
grant execute on function public.get_poll_results(bigint[]) to authenticated;
grant execute on function public.vote_poll(bigint, int[]) to authenticated;
