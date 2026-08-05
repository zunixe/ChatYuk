-- Fix RLS private_messages untuk blokir
-- Jalankan di Supabase Dashboard → SQL Editor

-- 1. Hapus policy lama
drop policy if exists "private_messages_select" on public.private_messages;
drop policy if exists "private_messages_insert" on public.private_messages;

-- 2. SELECT: sembunyikan pesan dari orang yang diblokir oleh penerima
create policy "private_messages_select" on public.private_messages
  for select using (
    exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Sembunyikan pesan dari orang yang saya blokir
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid()
        and b.blocked_id = private_messages.sender_id
    )
  );

-- 3. INSERT: tolak pesan jika pengirim diblokir oleh penerima
create policy "private_messages_insert" on public.private_messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.private_chats pc
      where pc.chat_id = private_messages.chat_id
        and auth.uid() = any (pc.participants)
    )
    -- Tolak jika pengirim diblokir oleh salah satu peserta lain
    and not exists (
      select 1 from public.blocks b
      join public.private_chats pc on pc.chat_id = private_messages.chat_id
      where b.blocked_id = auth.uid()
        and b.blocker_id = any (pc.participants)
        and b.blocker_id != auth.uid()
    )
  );
