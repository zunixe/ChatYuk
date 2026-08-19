-- Ambil alih nickname milik akun anon yang sudah tidak aktif > 7 hari.
-- Dummy (anon) yang di-uninstall tidak terhapus otomatis di server,
-- jadi nick-nya bisa di-claim oleh user baru.
create or replace function public.claim_nickname(p_nickname text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_registered boolean;
  v_last_seen timestamptz;
begin
  select id, coalesce(is_registered, false), coalesce(last_seen, created_at)
    into v_owner, v_registered, v_last_seen
    from profiles
   where nickname = p_nickname
   limit 1;

  -- Tidak ada pemilik / milik sendiri / akun ber-email — jangan sentuh.
  if v_owner is null or v_owner = auth.uid() or v_registered then
    return false;
  end if;

  -- Masih aktif dalam 7 hari terakhir — jangan di-claim.
  if v_last_seen > now() - interval '7 days' then
    return false;
  end if;

  -- Hapus relasi milik akun anon yatim (FK ke profiles).
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
$$;

revoke all on function public.claim_nickname(p_nickname text) from public;
grant execute on function public.claim_nickname(p_nickname text) to anon, authenticated;
