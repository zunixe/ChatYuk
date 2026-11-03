-- 2026-11-03: random_match_ping jangan kembalikan call MATI.
--
-- Baris `random_match_queue` menyimpan `matched_call_id` sampai
-- leave()/re-join. `random_match_ping` lama selalu menjawab 'matched'
-- selama kolom itu terisi — TANPA mengecek call masih hidup. Akibatnya
-- ping di sesi berikutnya mengembalikan callId call yang SUDAH ended →
-- client membuka CallSession untuk call mati di atas sesi hidup
-- (kamera/mic/pc ganda → lag + "layar kaya double").
--
-- Perbaikan: sebelum menjawab 'matched', validasi call
--   status = 'answered' AND coalesce(last_seen_at, answered_at, created_at)
--   segar (< 120 dtk — heartbeat client 25 dtk, zombie sweep admin 75 dtk;
--   120 dtk memberi margin ekstra supaya call hidup tak pernah dicabut).
-- Call mati/zombie → jejak pair dibersihkan → user tetap di antrean
-- ('waiting') sehingga bisa ter-pair ulang — bukan nyangkut di layar
-- "Menyambungkan…" selamanya.

create or replace function public.random_match_ping()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  row_q record;
  p_name text; p_gender text; p_age int; p_city text; p_avatar text;
  v_call_status text;
  v_seen timestamptz;
begin
  if me is null then raise exception 'Not authenticated'; end if;

  select * into row_q from public.random_match_queue where user_id = me;
  if not found then
    return jsonb_build_object('status', 'idle');
  end if;

  -- Sudah dipasangkan orang lain (jalur realtime bisa telat/hilang).
  if row_q.matched_call_id is not null then
    select c.status,
           coalesce(c.last_seen_at, c.answered_at, c.created_at)
      into v_call_status, v_seen
      from public.calls c where c.id = row_q.matched_call_id;
    -- Call MATI/ZOMBIE: status bukan 'answered' (ended/canceled/dst.)
    -- atau heartbeat basi ≥120 dtk. Jangan kembalikan callId mati —
    -- bersihkan jejak pair, user tetap antre (bisa ter-pair ulang).
    if v_call_status is distinct from 'answered'
       or coalesce(v_seen, '-infinity'::timestamptz)
          < now() - interval '120 seconds' then
      update public.random_match_queue
         set matched_call_id = null,
             matched_with = null,
             pinged_at = now()
       where user_id = me;
      return jsonb_build_object('status', 'waiting');
    end if;
    select p.nickname, p.gender, p.age, p.city,
           case when public.privacy_can_view(p.id, 'profile_photo', me)
                then p.avatar else '' end
      into p_name, p_gender, p_age, p_city, p_avatar
      from public.profiles p where p.id = row_q.matched_with;
    return jsonb_build_object(
      'status', 'matched',
      'call_id', row_q.matched_call_id,
      'is_caller', (select caller_id = me from public.calls where id = row_q.matched_call_id),
      'partner', jsonb_build_object(
        'uid', row_q.matched_with,
        'nickname', coalesce(p_name, 'User'),
        'gender', coalesce(p_gender, 'other'),
        'age', p_age,
        'city', p_city,
        'avatar', coalesce(p_avatar, ''),
        'distance_km', null
      )
    );
  end if;

  update public.random_match_queue set pinged_at = now() where user_id = me;
  return jsonb_build_object('status', 'waiting');
end;
$function$;
