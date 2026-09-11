-- ChatYuk: dedupe anti-race untuk balasan AI dummy.
-- Dua invokasi ai-reply yang bersamaan sama-sama lolos cek "sudah ada
-- balasan setelah trigger_msg_id?" (keduanya cek sebelum ada yang insert)
-- -> dua balasan untuk satu pesan. Claim table dgn PK = atomik.
-- ============================================================

create table if not exists public.ai_reply_claims (
  trigger_msg_id bigint primary key,
  dummy_uid uuid not null,
  claimed_at timestamptz not null default now()
);

-- RLS: hanya service_role (edge function) yang menyentuh tabel ini.
alter table public.ai_reply_claims enable row level security;
revoke all on table public.ai_reply_claims from anon, authenticated;
grant insert, select, delete on table public.ai_reply_claims to service_role;

-- Pengurus: baris lama (>1 jam) dibuang saat claim baru dimasukkan.
create or replace function public.ai_reply_claim(p_msg_id bigint, p_dummy uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  delete from public.ai_reply_claims where claimed_at < now() - interval '1 hour';
  begin
    insert into public.ai_reply_claims (trigger_msg_id, dummy_uid)
    values (p_msg_id, p_dummy);
    return true;
  exception when unique_violation then
    return false;
  end;
end;
$function$;
revoke execute on function public.ai_reply_claim(bigint, uuid) from public, anon;
grant execute on function public.ai_reply_claim(bigint, uuid) to service_role;
