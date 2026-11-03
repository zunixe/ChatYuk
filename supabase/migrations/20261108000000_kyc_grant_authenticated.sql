-- Grant eksekusi fungsi KYC untuk role `authenticated`.
--
-- Latar: fungsi `submit_kyc`, `get_my_kyc`, `admin_kyc_list`, dan
-- `admin_kyc_review` dibuat pada migrasi KYC awal TANPA grant — ACL live
-- hanya `postgres=X/postgres,service_role=X/postgres`, sehingga klien
-- Flutter (role authenticated) mendapat `permission denied for function`.
-- Halaman KYC baru (kyc_screen.dart) dan tab admin KYC membutuhkannya.
--
-- Keamanan:
--  - submit_kyc/get_my_kyc sudah scope `auth.uid()` di dalam body —
--    user hanya bisa submit & membaca pengajuannya sendiri.
--  - admin_kyc_list/admin_kyc_review sudah guard `auth.email()` di dalam
--    body → non-admin mendapat exception 'Unauthorized' walau bisa execute.
--  - `anon` tetap tanpa akses apa pun.
--
-- Fungsi KYC tidak masuk daftar FROZEN (cek scripts/frozen_functions.txt)
-- dan grant tidak mengubah body fungsi → snapshot tak perlu diperbarui.

grant execute on function public.submit_kyc(text, text, text, text, text, date)
  to authenticated;
grant execute on function public.get_my_kyc() to authenticated;
grant execute on function public.admin_kyc_list(text) to authenticated;
grant execute on function public.admin_kyc_review(uuid, boolean, text)
  to authenticated;
