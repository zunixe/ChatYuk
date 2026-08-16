-- ============================================================
-- ChatYuk: history poin (credit/debit) di profil
--
-- point_events sudah enable RLS tapi tanpa policy → user tidak
-- bisa SELECT history sendiri. Tambahkan policy select untuk
-- user yang bersangkutan (id = auth.uid()).
-- ============================================================

create policy "point_events_select_own"
  on public.point_events
  for select
  to authenticated
  using (user_id = auth.uid());

-- Pastikan anon/role lain tidak bisa baca history user lain
revoke select on public.point_events from anon, public;
grant select on public.point_events to authenticated;
