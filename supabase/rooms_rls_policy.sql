-- ============================================
-- ChatYuk: Izinkan lazy-seed room per negara
-- Room di-seed otomatis oleh app (upsert) saat
-- negara baru dipilih. Perlu policy INSERT & UPDATE.
-- ============================================

drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms
  for insert with check (true);

drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms
  for update using (true);