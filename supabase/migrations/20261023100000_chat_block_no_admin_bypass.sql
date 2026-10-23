-- Blokir berlaku untuk SEMUA pengirim — termasuk akun admin & service_role.
--
-- Bug (laporan owner 2026-10-23): user memblokir "ChatYuk Admin", tapi admin
-- tetap bisa mengirim pesan ke user itu (centang terkirim, pesan masuk).
-- Penyebab: `enforce_chat_block` (20261022000000) melewatkan cek bila
-- `is_admin_request()` — fungsi itu TRUE untuk email admin DAN
-- `auth.role() = 'service_role'`. Akibat ikutan: balasan AI dummy (edge
-- `ai-reply`, client service_role) juga menembus blokir.
--
-- Fix: hapus pengecualian. Blokir adalah hubungan antar DUA peserta chat;
-- siapa pun yang menulis pesan atas nama salah satunya wajib menghormatinya.
-- Cek admin tetap utuh di tempat lain (fungsi admin_* memakai
-- is_admin_request sendiri) — hanya trigger ini yang berubah.
--
-- SAFE: hanya mengganti body fungsi trigger public.enforce_chat_block (bukan
--       FROZEN); tidak menyentuh RLS/policy/grant/kolom. Fitur terdampak:
--       kirim pesan private (user, admin, AI dummy) ke/dari pihak yang
--       saling memblokir → ditolak 'blocked' (P0001), klien menampilkan
--       centang 1 (blokir senyap).

create or replace function public.enforce_chat_block()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_other uuid;
begin
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
