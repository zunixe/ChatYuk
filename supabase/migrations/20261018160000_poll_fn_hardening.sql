-- HARDENING: cabut EXECUTE fungsi POLL dari PUBLIC & anon.
--
-- Latar: `revoke execute ... from anon` TIDAK menghapus grant implisit
-- PUBLIC (default Postgres), jadi anon masih bisa memanggil RPC poll
-- (terverifikasi: has_function_privilege('anon',…)=true, padahal RPC lain
-- seperti pin_private_chat/mark_chat_read/mute_room = false).
-- Fungsi tetap memvalidasi di dalamnya (auth.uid() & peserta/anggota), tetapi
-- sebaiknya anon tak bisa memanggil sama sekali — sesuai konvensi proyek.
--
-- Berlaku untuk poll PRIVATE (20261018130000) maupun GRUP/GLOBAL ROOM
-- (20261018150000). Rutin: revoke/grant execute on function (tanpa ubah tabel).

revoke execute on function public.get_poll_results(bigint[]) from public, anon;
revoke execute on function public.vote_poll(bigint, int[]) from public, anon;
revoke execute on function public.get_room_poll_results(bigint[]) from public, anon;
revoke execute on function public.vote_room_poll(bigint, int[]) from public, anon;

grant execute on function public.get_poll_results(bigint[]) to authenticated;
grant execute on function public.vote_poll(bigint, int[]) to authenticated;
grant execute on function public.get_room_poll_results(bigint[]) to authenticated;
grant execute on function public.vote_room_poll(bigint, int[]) to authenticated;
