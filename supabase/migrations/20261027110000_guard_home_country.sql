-- NEGARA ASAL TIDAK BISA DIUBAH LEWAT `UPDATE profiles` LANGSUNG.
--
-- Celah yang dilaporkan user: "dimoderasi negara asal masih bisa dirubah
-- walau belum 30 hari". RPC `set_home_country` sudah menjaga cooldown 30
-- hari, TETAPI policy `profiles_update_own` hanya membatasi `auth.uid()=id`
-- sehingga klien bisa `update profiles set home_country='XX'` kapan saja —
-- melewati cooldown (dan melewati izin lintas negara).
--
-- Perbaikan: trigger BEFORE UPDATE yang MENGEMBALIKAN nilai lama bila
-- perubahan tidak datang dari RPC resmi (yang menandai dirinya lewat
-- `current_setting('chatyuk.home_country_ok')`) atau dari admin.
--
-- Catatan: `home_country_changed_at` juga dikunci supaya cooldown tidak bisa
-- di-reset dari klien.
--
-- SAFE: 1 fungsi trigger + 1 trigger BEFORE UPDATE pada `profiles`.
--       Mengembalikan (bukan melempar error) nilai lama → klien lama yang
--       mengirim ulang seluruh baris profil tidak gagal.
--       Fitur terdampak: perubahan "negara asal" hanya lewat RPC Profil.
create or replace function public.guard_home_country()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_trusted boolean :=
    coalesce(current_setting('chatyuk.home_country_ok', true), '') = '1';
begin
  -- Tidak ada perubahan → tidak perlu apa pun.
  if new.home_country is not distinct from old.home_country
     and new.home_country_changed_at is not distinct from old.home_country_changed_at then
    return new;
  end if;

  if v_trusted or public.is_chatyuk_admin(auth.uid()) then
    return new;
  end if;

  -- Tidak berwenang: pertahankan nilai lama (tanpa error agar update lain
  -- pada baris yang sama tetap berhasil).
  new.home_country := old.home_country;
  new.home_country_changed_at := old.home_country_changed_at;
  return new;
end;
$function$;

drop trigger if exists guard_home_country_trg on public.profiles;
create trigger guard_home_country_trg
  before update of home_country, home_country_changed_at on public.profiles
  for each row execute function public.guard_home_country();

-- ── RPC resmi jadi "trusted" + perbaikan cooldown ──────────────────────────
create or replace function public.set_home_country(p_country text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me       uuid := auth.uid();
  v_cur    text;
  v_changed timestamptz;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_country, '') = '' then
    raise exception 'country_required' using errcode = '22023';
  end if;

  select home_country, home_country_changed_at
    into v_cur, v_changed
    from public.profiles where id = me;

  if v_cur is not null and v_cur = p_country then
    return jsonb_build_object('ok', true, 'unchanged', true);
  end if;

  -- Saat pertama kali diisi (NULL) → bebas; setelah itu maks 1x / 30 hari.
  if v_changed is not null and v_changed > now() - interval '30 days' then
    return jsonb_build_object(
      'ok', false,
      'error', 'cooldown',
      'next_change_at', (v_changed + interval '30 days')
    );
  end if;

  -- Tandai update ini SAH agar trigger guard_home_country mengizinkannya.
  perform set_config('chatyuk.home_country_ok', '1', true);

  update public.profiles
     set home_country = p_country,
         home_country_changed_at = now()
   where id = me;

  perform set_config('chatyuk.home_country_ok', '', true);

  return jsonb_build_object('ok', true, 'home_country', p_country);
end;
$function$;

revoke execute on function public.set_home_country(text) from public, anon;
grant execute on function public.set_home_country(text) to authenticated;

-- ── Klien butuh tahu negara asalnya sendiri ────────────────────────────────
-- `profile_public` belum mengembalikan `home_country`, sehingga UI tidak
-- pernah tahu negara asal user → tombol "Ajukan moderator" / "Buka konsol"
-- mengirim string kosong dan selalu gagal. Hanya dikirim untuk DIRI SENDIRI.
create or replace function public.profile_public(p_user uuid default auth.uid())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  r public.profiles%rowtype;
  me uuid := auth.uid();
  v_is_me boolean := (p_user = auth.uid());
begin
  select * into r from public.profiles where id = p_user;
  if r.id is null then return '{}'::jsonb; end if;

  return jsonb_build_object(
    'id', r.id,
    'nickname', r.nickname,
    'gender', r.gender,
    'age', r.age,
    'country', r.country,
    'city', r.city,
    'status', case when public.privacy_can_view(r.id, 'presence', me)
                   then r.status else 'offline' end,
    'avatar', case when public.privacy_can_view(r.id, 'profile_photo', me) then r.avatar else '' end,
    'is_registered', r.is_registered,
    'needs_onboarding', coalesce(r.needs_onboarding, false),
    'login_at', r.login_at,
    'created_at', r.created_at,
    'last_seen', case when public.privacy_can_view(r.id, 'last_seen', me) then r.last_seen else null end,
    'about', case when public.privacy_can_view(r.id, 'about', me) then r.about else '' end,
    'hashtags', r.hashtags,
    'points', case when r.id = me then r.points else 0 end,
    'share_location', case when r.id = me then r.share_location else false end,
    'followers_count', r.followers_count,
    'following_count', r.following_count,
    'subscriber_count', r.subscriber_count,
    'subscription_price', r.subscription_price,
    'friends_count', r.friends_count,
    'phone', case when v_is_me then coalesce(r.phone, '') else '' end,
    'birth_date', case when v_is_me then r.birth_date else null end,
    'phone_verified_at',
      case when v_is_me then r.phone_verified_at else null end,
    -- Negara asal (untuk izin lintas negara & lamaran moderator).
    'home_country', case when v_is_me then r.home_country else null end,
    'home_country_changed_at',
      case when v_is_me then r.home_country_changed_at else null end
  );
end;
$function$;
