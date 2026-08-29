-- Relax profiles UPDATE policy — hapus WITH CHECK yang terlalu ketat
-- Sebelumnya: with_check mensyaratkan nickname 3-20 karakter, status valid,
-- points unchanged. Ini BLOCK semua update termasuk updateAvatar,
-- markRegistered, goOnline — karena banyak user punya nickname kosong
-- atau profile incomplete.
-- Sekarang: cukup auth.uid() = id di USING + WITH CHECK (security tetap)
drop policy if exists "profiles_update_own" on public.profiles;
CREATE POLICY "profiles_update_own"
ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);
