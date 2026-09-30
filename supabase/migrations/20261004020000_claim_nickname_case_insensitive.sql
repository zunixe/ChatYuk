-- ============================================================
-- claim_nickname case-insensitive (selaras unique index lower(nickname)).
--
-- LATAR: setelah `profiles_nickname_lower_unique` dipasang, pengecekan
--   nickname di klien jadi case-insensitive. `claim_nickname` juga harus
--   case-insensitive supaya "Budi" bisa mengklaim nickname anon mati
--   bernama "budi" (kalau tidak, tetap tidak ketemu → gagal klaim).
--
-- Perubahan: WHERE nickname = p_nickname → lower(trim(nickname)) =
--   lower(trim(p_nickname)). Sisa logika TIDAK diubah.
--
-- Tidak FROZEN. Apply via Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

create or replace function public.claim_nickname(p_nickname text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_owner uuid;
  v_registered boolean;
  v_last_seen timestamptz;
  v_new_nick text;
begin
  if public.is_banned_nickname(p_nickname)
     and not public.is_admin_request() then
    return false;
  end if;

  select id, coalesce(is_registered, false), coalesce(last_seen, created_at)
    into v_owner, v_registered, v_last_seen
    from profiles
   where lower(trim(nickname)) = lower(trim(p_nickname))
   limit 1;

  if v_owner is null or v_owner = auth.uid() or v_registered then
    return false;
  end if;

  if v_last_seen > now() - interval '7 days' then
    return false;
  end if;

  -- Nickname baru pengambil (kalau dia sedang mengubah nickname ke ini).
  select nickname into v_new_nick from profiles where id = auth.uid();

  perform public.fn_archive_deleted_user(v_owner, 'nickname_claim', auth.uid(), v_new_nick);

  delete from comment_likes where user_id = v_owner;
  delete from comment_shares where user_id = v_owner;
  delete from contact_messages where user_id = v_owner;
  delete from follows where follower_id = v_owner or followee_id = v_owner;
  delete from friend_requests where from_id = v_owner or to_id = v_owner;
  delete from kyc_requests where user_id = v_owner;
  delete from post_comments where author_id = v_owner;
  delete from post_likes where user_id = v_owner;
  delete from post_shares where user_id = v_owner;
  delete from posts where author_id = v_owner;
  delete from referral_rewards where referred_id = v_owner or referrer_id = v_owner;
  delete from subscriptions where subscriber_id = v_owner or creator_id = v_owner;
  delete from user_photos where user_id = v_owner;
  delete from withdrawal_requests where user_id = v_owner;

  delete from profiles where id = v_owner;
  return true;
end;
$function$;

revoke all on function public.claim_nickname(p_nickname text) from public; -- SAFE: hardening RPC klaim nickname; grant execute tetap ke anon/authenticated (fitur klaim nickname + registrasi) — hanya cabut default PUBLIC, tidak mengubah akses sah.
grant execute on function public.claim_nickname(p_nickname text) to anon, authenticated;
