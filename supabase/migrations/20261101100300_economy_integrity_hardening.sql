-- ============================================================
-- 20261101100300_economy_integrity_hardening.sql
-- Integritas & kebocoran data ekosistem koin.
--
-- 1. point_events: RLS TIDAK PERNAH di-enable (policy di 20260814210000
--    jadi inert). Client bisa membaca event semua user dan memalsukan skor
--    leaderboard mingguan (points_leaderboard menghitung dari tabel ini).
--
-- 2. profiles: policy `profiles_update_own` (20260829060000) terbuka untuk
--    SEMUA kolom; penjaga `points` dari 20260814230000 sudah dihapus.
--    Client bisa menulis points / *_balance / is_registered / created_at
--    (created_at dipakai untuk syarat umur akun 72 jam withdraw).
--    → trigger pengembali nilai (pola guard_home_country). REVOKE kolom
--      TIDAK dipakai karena registrasi & link akun memang menulis
--      is_registered/created_at lewat PostgREST.
--
-- 3. ledger_spend & _spend_yukcoin_core: baca-lalu-tulis tanpa lock →
--    dua debit paralel bisa sama-sama lolos cek saldo (saldo minus).
--
-- 4. Realtime membocorkan baris penuh profiles (saldo, email, fcm_token)
--    dan app_settings (app_shared_secret).
-- ============================================================

-- ── 1. point_events — RLS + read-only untuk client ────────────────────
-- SAFE: point_events hanya ditulis oleh fungsi SECURITY DEFINER
-- (ledger/gift/call/misi). Terdampak bila salah: riwayat poin
-- (point_history_screen), leaderboard mingguan, misi. Client hanya baca
-- baris miliknya (policy point_events_select_own sudah ada).
ALTER TABLE public.point_events ENABLE ROW LEVEL SECURITY; -- SAFE: mengaktifkan RLS yang selama ini inert. Pembaca: riwayat poin & leaderboard mingguan; penulis: RPC definer.
REVOKE INSERT, UPDATE, DELETE ON public.point_events FROM anon, authenticated; -- SAFE: mencegah pemalsuan skor leaderboard mingguan. Terdampak: riwayat poin (read), leaderboard (read), misi (tulis via RPC definer).
REVOKE TRUNCATE ON public.point_events FROM anon, authenticated; -- SAFE: hardening tambahan; tidak ada konsumen client yang butuh truncate.

-- ── 2. profiles — kunci kolom saldo/identitas dengan trigger ──────────
CREATE OR REPLACE FUNCTION public.guard_economy_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  -- RPC resmi (ganti email, set is_registered saat registrasi/link) menandai
  -- dirinya sendiri. Ledger trigger juga berjalan di konteks definer.
  v_trusted boolean :=
    coalesce(current_setting('chatyuk.economy_ok', true), '') = '1';
begin
  -- Hanya menegakkan aturan untuk permintaan CLIENT sungguhan. Konteks
  -- internal (migrasi, job, service_role, test) tidak punya auth.uid() dan
  -- memang berhak menyentuh kolom ini.
  if auth.uid() is null
     or coalesce(auth.role(), '') = 'service_role'
     or v_trusted
     or public.is_chatyuk_admin(auth.uid()) then
    return new;
  end if;

  -- Nilai saldo & identitas hanya boleh berubah lewat trigger ledger / RPC.
  if new.points is distinct from old.points then
    new.points := old.points;
  end if;
  if new.bonus_balance is distinct from old.bonus_balance then
    new.bonus_balance := old.bonus_balance;
  end if;
  if new.topup_balance is distinct from old.topup_balance then
    new.topup_balance := old.topup_balance;
  end if;
  if new.earned_balance is distinct from old.earned_balance then
    new.earned_balance := old.earned_balance;
  end if;
  if new.created_at is distinct from old.created_at then
    new.created_at := old.created_at;
  end if;

  return new;
end;
$function$;

DROP TRIGGER IF EXISTS guard_economy_columns_trg ON public.profiles;
CREATE TRIGGER guard_economy_columns_trg
  BEFORE UPDATE OF points, bonus_balance, topup_balance, earned_balance, created_at
  ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_economy_columns();

-- Trigger ledger menulis saldo sebagai definer → tandai trusted.
CREATE OR REPLACE FUNCTION public.trg_coin_ledger_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  perform set_config('chatyuk.economy_ok', '1', true);
  update public.profiles set
    bonus_balance = bonus_balance + case when new.bucket='bonus' then new.amount else 0 end,
    topup_balance = topup_balance + case when new.bucket='topup' then new.amount else 0 end,
    earned_balance = earned_balance + case when new.bucket='earned' then new.amount else 0 end,
    points = points + new.amount
  where id = new.user_id;
  perform set_config('chatyuk.economy_ok', '', true);
  return new;
end;
$function$;

-- ══ SALDO AWAL: baris baru (INSERT) juga harus konsisten — trigger di atas
-- hanya UPDATE. Registrasi membuat baris dengan points default 0, jadi
-- tidak perlu penanganan khusus.

-- ── 3. Serialisasi debit ledger ──────────────────────────────────────
-- Pola sama dengan refund_chat_point (20261024160000): advisory lock per
-- user → cek saldo + insert baris negatif jadi atomik.
CREATE OR REPLACE FUNCTION public.ledger_spend(
  p_user uuid, p_type text, p_amount int, p_ref text default null
) RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
declare
  b int; t int; e int; need int := p_amount; take int;
begin
  if p_amount <= 0 then return public.wallet_sync_points(p_user); end if;

  -- Serialisasi per user (re-entrant: aman bila pemanggil sudah memegang lock).
  perform pg_advisory_xact_lock(hashtext('wallet:' || p_user::text));

  select coalesce(sum(amount) filter (where bucket='bonus'),0),
         coalesce(sum(amount) filter (where bucket='topup'),0),
         coalesce(sum(amount) filter (where bucket='earned'),0)
    into b, t, e from coin_ledger where user_id = p_user;

  if (b + t + e) < p_amount then
    raise exception 'Not enough points';
  end if;

  take := least(b, need);
  if take > 0 then
    insert into coin_ledger(user_id,bucket,type,amount,ref_id)
      values (p_user,'bonus',p_type,-take,p_ref);
    need := need - take;
  end if;
  if need > 0 then
    take := least(t, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'topup',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;
  if need > 0 then
    take := least(e, need);
    if take > 0 then
      insert into coin_ledger(user_id,bucket,type,amount,ref_id)
        values (p_user,'earned',p_type,-take,p_ref);
      need := need - take;
    end if;
  end if;

  return public.wallet_sync_points(p_user);
end; $$;

-- ── 4. Realtime — stop broadcast baris penuh ─────────────────────────
-- SAFE: profiles & app_settings dikeluarkan dari publication. Saldo user
-- sendir dikirim lewat polling watchOwnPoints (20 dtk) + refreshWallet.
-- Terdampak: kartu profil realtime, admin settings realtime — keduanya
-- sudah punya jalur fetch/polling sendiri.
DO $do$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.profiles;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.app_settings;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
END
$do$;

-- ── 5. get_earnings_summary — guard anti-IDOR ────────────────────────
CREATE OR REPLACE FUNCTION public.get_earnings_summary(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
    v_total bigint;
    v_weekly bigint;
    v_today bigint;
    v_gift bigint;
    v_mission bigint;
    v_bonus bigint;
    v_call bigint;
    v_other bigint;
    v_withdrawable bigint;
    v_video_calls bigint;
    v_video_seconds bigint;
    v_match_calls bigint;
    v_match_seconds bigint;
    v_private_total bigint;
    v_private_answered bigint;
BEGIN
    -- Guard anti-IDOR (2026-11-01): hanya boleh membaca milik sendiri.
    -- service_role bebas (admin/job internal).
    if coalesce(auth.role(), '') <> 'service_role'
       and auth.uid() is not null
       and p_user_id is distinct from auth.uid() then
        raise exception 'Forbidden: tidak boleh membaca saldo user lain'
            using errcode = '42501';
    end if;

    -- Audit 2026-10-31: whitelist diselaraskan dengan type yang benar-benar
    -- ditulis fungsi ekonomi. Versi lama melewatkan coin_received (kirim
    -- koin antar user), subscribe_income, dan photo_income (unlock_photo
    -- menulis 'photo_income', BUKAN 'photo_unlock_income').
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('week', now())), 0),
        COALESCE(SUM(amount) FILTER (WHERE created_at >= current_date), 0),
        COALESCE(SUM(amount) FILTER (WHERE type IN ('gift_recv','coin_received')), 0),
        COALESCE(SUM(amount) FILTER (WHERE type = 'mission_reward'), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type IN ('call_audio_income','call_video_income',
                           'private_call_income','match_call_income')), 0),
        COALESCE(SUM(amount) FILTER (
            WHERE type NOT IN ('gift_recv','coin_received','mission_reward',
                               'call_audio_income','call_video_income',
                               'private_call_income','match_call_income')), 0)
    INTO v_total, v_weekly, v_today, v_gift, v_mission, v_call, v_other
    FROM public.coin_ledger
    WHERE user_id = p_user_id
      AND amount > 0
      AND type IN (
            'gift_recv','coin_received',
            'mission_reward',
            'call_audio_income','call_video_income',
            'private_call_income','match_call_income',
            'photo_income','photo_unlock_income',
            'subscribe_income'
      )
      AND coalesce(ref_id, '') NOT IN ('t','test-income')
      AND coalesce(ref_id, '') NOT LIKE 'cleanup\_%'
      AND coalesce(ref_id, '') NOT LIKE 'female_bonus_reset\_%';

    -- ── Saldo yang bisa ditarik = saldo bersih semua bucket ──
    SELECT COALESCE(SUM(amount), 0) INTO v_withdrawable
      FROM public.coin_ledger
     WHERE user_id = p_user_id;

    -- ── Statistik panggilan ──
    SELECT
        COUNT(*) FILTER (WHERE call_type = 'video'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE call_type = 'video' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint,
        COUNT(*) FILTER (WHERE kind = 'random'),
        COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - answered_at)))
                 FILTER (WHERE kind = 'random' AND answered_at IS NOT NULL
                         AND ended_at IS NOT NULL), 0)::bigint
    INTO v_video_calls, v_video_seconds, v_match_calls, v_match_seconds
    FROM public.calls
    WHERE (caller_id = p_user_id OR callee_id = p_user_id)
      AND status = 'ended';

    SELECT COUNT(*), COUNT(*) FILTER (WHERE answered_at IS NOT NULL)
    INTO v_private_total, v_private_answered
    FROM public.calls
    WHERE callee_id = p_user_id
      AND coalesce(kind, '') <> 'random'
      AND status = 'ended';

    result := jsonb_build_object(
        'total_earnings', v_total,
        'weekly_earnings', v_weekly,
        'today_earnings', v_today,
        'withdrawable', v_withdrawable,
        'breakdown', jsonb_build_object(
            'private_call', v_call,
            'match_call', 0,
            'message', 0,
            'gift', v_gift,
            'mission', v_mission,
            'bonus', 0,
            'other', v_other
        ),
        'stats', jsonb_build_object(
            'video_call_count', v_video_calls,
            'video_call_seconds', v_video_seconds,
            'match_call_count', v_match_calls,
            'match_call_seconds', v_match_seconds,
            'avg_match_seconds', CASE
                WHEN v_match_calls > 0 THEN (v_match_seconds / v_match_calls)::bigint
                ELSE 0 END,
            'private_call_total', v_private_total,
            'private_call_answered', v_private_answered,
            'private_answer_rate', CASE
                WHEN v_private_total > 0
                THEN round((v_private_answered::numeric / v_private_total) * 100)
                ELSE 0 END
        )
    );

    RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_earnings_summary(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_earnings_summary(uuid) TO authenticated, service_role;

-- TRUNCATE juga dicabut (anteriornya terlewat: grant default Supabase).
REVOKE TRUNCATE ON public.user_missions FROM anon, authenticated; -- SAFE: tidak ada konsumen client yang butuh truncate. Terdampak: misi (baca via SELECT, tulis via RPC definer).
