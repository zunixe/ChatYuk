-- Blokir DUA ARAH ditegakkan di server.
--
-- Sebelumnya blokir hanya dicek di klien (web: useBlocks/otherBlocked,
-- mobile: chat.isBlocked). Klien lain / API langsung tetap bisa mengirim.
-- Trigger ini menutup celah tersebut TANPA mengubah perilaku UI:
-- - A memblokir B  -> B tidak bisa kirim ke A  DAN  A tidak bisa kirim ke B
-- - setelah unblock -> kembali normal
--
-- Admin/service_role dikecualikan (is_admin_request sudah dipakai di repo).
-- SAFE: menambah trigger baru pada public.private_messages; tidak mengubah
--       policy/RLS, tidak mengubah kolom, tidak menyentuh tabel lain.
--       Fitur terdampak: chat private (web & mobile) — perilaku blokir saja.

create or replace function public.enforce_chat_block()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_other uuid;
begin
  if public.is_admin_request() then
    return new;
  end if;

  -- Lawan bicara diambil dari table (bukan dari payload klien).
  select p2
    into v_other
    from (
      select unnest(pc.participants) as p2
        from public.private_chats pc
       where pc.chat_id = new.chat_id
    ) x
   where p2 <> new.sender_id
   limit 1;

  if v_other is null then
    return new; -- chat tidak ditemukan / bukan 1:1: biarkan policy yang menilai
  end if;

  if exists (
    select 1
      from public.blocks b
     where (b.blocker_id = new.sender_id and b.blocked_id = v_other)
        or (b.blocker_id = v_other and b.blocked_id = new.sender_id)
  ) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_chat_block_trg on public.private_messages;
create trigger enforce_chat_block_trg
  before insert on public.private_messages
  for each row execute function public.enforce_chat_block();
