-- ============================================================
-- ChatYuk: Fix 50 poin awal tidak masuk ledger
--
-- Gejala: user baru (anon/email/Gmail) terlihat saldo 0, kadang
-- 50 → 0. Penyebab: profiles.points dapat 50 dari column default,
-- TAPI coin_ledger (sumber kebenaran saldo) kosong → get_wallet()
-- mengembalikan 0 dan menimpa cache 50 di client.
--
-- Fix:
--   1. Trigger AFTER INSERT pada profiles → tulis entry 'signup'
--      ke coin_ledger (bucket bonus) bila user belum punya ledger.
--      SECURITY DEFINER: coin_ledger menolak INSERT dari role client,
--      jadi trigger harus jalan sebagai pemilik (postgres).
--   2. Backfill user lama yang belum punya ledger.
-- ============================================================

create or replace function public.profiles_ledger_signup()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.coin_ledger where user_id = NEW.id) then
    insert into public.coin_ledger (user_id, bucket, type, amount, metadata)
    values (NEW.id, 'bonus', 'signup', coalesce(NEW.points, 50),
            jsonb_build_object('reason', 'signup'));
    update public.profiles set points = coalesce(NEW.points, 50) where id = NEW.id;
  end if;
  return NEW;
end; $$;

drop trigger if exists profiles_ledger_signup_trg on public.profiles;
create trigger profiles_ledger_signup_trg after insert on public.profiles
  for each row execute function public.profiles_ledger_signup();

-- Backfill: user yang sudah ada tapi belum punya ledger sama sekali
-- (mis. daftar anon setelah wallet migration) → catat saldo lamanya.
insert into public.coin_ledger (user_id, bucket, type, amount, metadata)
select p.id, 'bonus', 'signup', p.points, jsonb_build_object('reason', 'signup')
from public.profiles p
where p.points > 0
  and not exists (select 1 from public.coin_ledger l where l.user_id = p.id);
