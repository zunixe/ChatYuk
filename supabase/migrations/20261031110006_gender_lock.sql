-- ══════════════════════════════════════════════════════════════════════
-- Lock gender — dipilih SEKALI, tidak bisa diubah setelahnya.
--
-- Alasan: gender menentukan seluruh ekonomi (female: misi/penghasilan/
-- withdraw; male: bayar koin). Tanpa lock, male bisa topup → pindah ke
-- female → withdraw → platform rugi.
--
-- Pola mengikuti `guard_country_lock`: revert SENYAP (update kolom lain pada
-- baris yang sama tetap berhasil) + bypass admin.
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. Kolom lock ──
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS gender_locked boolean NOT NULL DEFAULT false;

-- ── 2. Trigger guard ──
CREATE OR REPLACE FUNCTION public.guard_gender_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  -- Tidak ada perubahan gender → lolos (update kolom lain bebas),
  -- TAPI status lock WAJIB mengikuti nilai lama: client dilarang
  -- membuka kunci sendiri (`gender_locked=false`).
  if new.gender is not distinct from old.gender then
    new.gender_locked := old.gender_locked;
    return new;
  end if;

  -- Admin boleh mengoreksi (mis. salah daftar).
  if public.is_chatyuk_admin(auth.uid()) then
    new.gender_locked := true;
    return new;
  end if;

  -- Terkunci → pertahankan nilai lama (tanpa error agar update kolom lain
  -- pada baris yang sama tetap berhasil). Client juga tidak bisa memaksa
  -- `gender_locked=false` karena nilainya dipulihkan di sini.
  if old.gender_locked then
    new.gender := old.gender;
    new.gender_locked := true;
    return new;
  end if;

  -- Perubahan pertama sah → langsung kunci.
  new.gender_locked := true;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_guard_gender_lock ON public.profiles;
CREATE TRIGGER trg_guard_gender_lock
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.guard_gender_lock();

-- ── 3. Backfill retroaktif: kunci user yang SUDAH punya aktivitas ──
-- (232 user dengan riwayat koin; cegah eksploitasi male→female→withdraw)
UPDATE public.profiles SET gender_locked = true
WHERE id IN (
    SELECT user_id FROM public.coin_ledger WHERE user_id IS NOT NULL
    UNION
    SELECT user_id FROM public.user_missions WHERE user_id IS NOT NULL
    UNION
    SELECT user_id FROM public.withdrawal_requests WHERE user_id IS NOT NULL
);

-- ── 4. Cegah client menulis kolom lock langsung ──
-- (RLS profiles_update_own terbuka untuk semua kolom; trigger sudah
-- memulihkan nilainya, ini lapis kedua.)
REVOKE UPDATE (gender_locked) ON public.profiles FROM authenticated, anon; -- SAFE: kolom baru `gender_locked`; hanya guard trigger yang boleh menulis. Terdampak: ekonomi koin (female/male), misi, withdraw, bonus. UPDATE kolom profil lain TIDAK terpengaruh (grant per-kolom).

COMMENT ON COLUMN public.profiles.gender_locked IS
    'true = gender terkunci permanen (dipilih sekali). Dijaga trigger guard_gender_lock.';
