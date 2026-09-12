-- Pause AI per chat: typing ping (lawan sedang ngetik) + vacuum
-- (intervensi admin → AI diam 5 menit sebelum ambil alih).
-- RLS enable TANPA policy: client menulis via RPC ping_typing (security
-- definer); ai-reply baca via service role.
create table if not exists public.chat_ai_pause (
  chat_id text primary key,
  typing_at timestamptz,
  vacuum_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.chat_ai_pause enable row level security;

-- Client panggil saat mengetik (throttle 2.5s di sisi app).
create or replace function public.ping_typing(p_chat_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.chat_ai_pause (chat_id, typing_at, updated_at)
  values (p_chat_id, now(), now())
  on conflict (chat_id) do update
    set typing_at = now(), updated_at = now();
end;
$$;
revoke execute on function public.ping_typing(text) from public, anon;
grant execute on function public.ping_typing(text) to authenticated, service_role;
