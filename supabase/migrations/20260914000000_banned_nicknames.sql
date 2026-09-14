-- Blokir nickname mengandung zaini/hafid (substring, case-insensitive).
-- Kecuali admin (is_admin_request). Akun lama yang melanggar di-rename
-- paksa + offline; login mereka diblokir di gerbang aplikasi.

-- 1. Fungsi cek normalisasi: lowercase + buang spasi/_/-.
create or replace function public.is_banned_nickname(p_nickname text)
returns boolean
language sql
immutable
set search_path to 'public'
as $$
  select p_nickname is not null and (
    regexp_replace(lower(trim(p_nickname)), '[\s_\-]+', '', 'g') like '%zaini%'
    or regexp_replace(lower(trim(p_nickname)), '[\s_\-]+', '', 'g') like '%hafid%'
  )
$$;

-- 2. Trigger: tolak INSERT/UPDATE nickname terlarang (non-admin).
create or replace function public.trg_ban_nickname()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.is_banned_nickname(new.nickname)
     and not public.is_admin_request() then
    raise exception 'nickname_banned';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_ban_nickname on public.profiles;
create trigger trg_profiles_ban_nickname
  before insert or update of nickname on public.profiles
  for each row execute function public.trg_ban_nickname();

-- 3. Guard claim_nickname: nickname terlarang tidak bisa diklaim.
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
   where nickname = p_nickname
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

-- 4. Rename paksa akun lama yang melanggar (kecuali admin & dummy admin).
update public.profiles p
set nickname = 'User_' || substr(p.id::text, 1, 8),
    status = 'offline',
    last_seen = now()
where public.is_banned_nickname(p.nickname)
  and coalesce(lower(p.email), '') <> 'zunixe@gmail.com'
  and not exists (select 1 from public.dummy_accounts d where d.uid = p.id);
