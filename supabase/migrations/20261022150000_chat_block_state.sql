-- Status BLOKIR dua arah untuk satu lawan bicara — tanpa membocorkan siapa
-- memblokir siapa.
--
-- Masalah yang ditutup:
--   RLS `blocks` hanya mengizinkan SELECT baris milik sendiri
--   (`auth.uid() = blocker_id`) — itu BENAR untuk privasi, tapi akibatnya
--   klien tidak pernah tahu bila DIRINYA diblokir orang lain. Gejalanya:
--   user mengetik → bubble tampil (optimistis) → INSERT ditolak trigger
--   `enforce_chat_block` ('blocked', P0001) → pesan hilang tanpa penjelasan.
--
-- Solusi: fungsi ini HANYA mengembalikan 3 boolean (tanpa id/nama):
--   i_blocked_other  : saya memblokir dia
--   other_blocked_me : dia memblokir saya
--   can_send         : boleh kirim (tidak ada blokir di kedua arah)
--
-- Pemakaian: klien cek sekali di awal chat (dan setelah blokir/unblokir)
-- untuk menonaktifkan composer + menampilkan alasan, PERSIS seperti WhatsApp.
-- Server tetap menjadi penjaga terakhir lewat trigger.
--
-- SAFE: hanya menambah fungsi baru (read-only, security definer agar bisa
--       membaca baris blokir milik ORANG LAIN untuk menghasilkan boolean).
--       Tidak menyentuh RLS/policy/grant tabel mana pun.
--       Fitur terdampak: chat private (indikator blokir di composer).
create or replace function public.chat_block_state(p_other uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  v_i_blocked boolean := false;
  v_other_blocked boolean := false;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_other is null or p_other = me then
    return jsonb_build_object(
      'i_blocked_other', false,
      'other_blocked_me', false,
      'can_send', true
    );
  end if;

  select exists (
           select 1 from public.blocks b
            where b.blocker_id = me and b.blocked_id = p_other
         ),
         exists (
           select 1 from public.blocks b
            where b.blocker_id = p_other and b.blocked_id = me
         )
    into v_i_blocked, v_other_blocked;

  return jsonb_build_object(
    'i_blocked_other', v_i_blocked,
    'other_blocked_me', v_other_blocked,
    'can_send', not (v_i_blocked or v_other_blocked)
  );
end;
$function$;

revoke execute on function public.chat_block_state(uuid) from public, anon;
grant execute on function public.chat_block_state(uuid) to authenticated, service_role;
