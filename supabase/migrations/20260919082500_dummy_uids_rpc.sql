-- dummy_uids(): daftar uid dummy untuk client (presence cross-reference).
-- Latar: dummy_accounts RLS admin-only (dummy_admin_all) sehingga
-- ChatService._fetchDummyUids() dari HP user biasa selalu dapat set kosong
-- (RLS mengembalikan 0 baris, bukan error) → dummy yang statusnya idle
-- gugur sebagai "idle zombie" di filterRpcOnlineRows, padahal idle dummy
-- HARUS tampil (daftar online app). Gejala: Sarah (online) tampil,
-- Dhanu (idle) hilang di app, padahal di admin keduanya ada.
-- RPC security-definer ini HANYA membuka kolom uid — RLS/policy yang ada
-- tidak disentuh, kolom lain (persona, mood, jadwal) tetap admin-only.
create or replace function public.dummy_uids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select uid from public.dummy_accounts where uid is not null;
$$;
grant execute on function public.dummy_uids() to authenticated, anon;
