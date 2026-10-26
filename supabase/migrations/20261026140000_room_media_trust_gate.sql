-- TRUST GATE + RATE LIMIT untuk MEDIA di ROOM PUBLIK
-- (permintaan user 2026-10-26: hentikan kirim foto/video porn sembarangan
--  di global room).
--
-- MASALAH: di room publik (is_private=false) SIAPA PUN yang terdaftar bisa
-- mengirim foto/video. Tidak ada gate umur akun, tidak ada rate limit, tidak
-- ada verifikasi konten. Satu-satunya pertahanan = admin yang kebetulan
-- sedang melihat.
--
-- ATURAN (keputusan produk):
--   * Room PRIVAT & grup → TIDAK berubah (bebas).
--   * Room PUBLIK, kirim MEDIA (image/video/video_once) → wajib:
--       (1) umur akun >= media_trust_min_days  DAN
--       (2) jumlah pesan di ROOM PUBLIK >= media_trust_min_msgs
--     Atau moderator negara room itu / admin (bypass).
--   * RATE LIMIT: media_rate_per_min / media_rate_per_hour per user per room.
--   * Hanya MEDIA yang dibatasi — teks/voice/lokasi tetap bebas (agar diskusi
--     tidak mati).
--   * Akun TIDAK dihukum — hanya tombol media yang ditahan sampai syarat
--     terpenuhi (dan gate ini otomatis lolos seiring aktivitas).
--
-- Catatan: gate dijalankan di TRIGGER (bukan hanya klien) supaya klien
-- dimodifikasi / REST langsung tetap tertahan.
--
-- SAFE: aditif (kolom app_settings baru) + fungsi baru + trigger BARU pada
--       messages. Tidak mengubah policy/RLS yang ada, tidak mengubah kolom
--       pesan, tidak menyentuh tabel lain.
--       Fitur terdampak: kirim foto/video di ROOM PUBLIK saja.
--       Room privat, grup, private chat, dan semua pesan non-media TIDAK
--       terpengaruh.

-- ── 1. Konfigurasi (bisa diubah admin tanpa rilis) ─────────────────────────
alter table public.app_settings
  add column if not exists media_trust_min_days   integer not null default 3,
  add column if not exists media_trust_min_msgs   integer not null default 20,
  add column if not exists media_rate_per_min     integer not null default 3,
  add column if not exists media_rate_per_hour    integer not null default 20,
  add column if not exists nsfw_reject_threshold  numeric  not null default 0.75,
  add column if not exists nsfw_review_threshold  numeric  not null default 0.50;

-- ── 2. Tipe pesan yang dianggap MEDIA (dibatasi gate) ──────────────────────
create or replace function public.is_room_media_type(p_type text)
returns boolean
language sql
immutable
as $function$
  select coalesce(p_type in (
    'image', 'video', 'video_once', 'video_once_expired'
  ), false);
$function$;

-- ── 3. Gate trust ──────────────────────────────────────────────────────────
-- true  = boleh mengirim media di room tsb
-- false = ditolak (akun terlalu baru / aktivitas kurang / beda negara belum izin)
--
-- CATATAN Fase 4 (izin lintas negara) akan MENAMBAH cek `home_country` +
-- `country_send_permits` di fungsi ini; struktur sudah disiapkan.
create or replace function public.can_send_room_media(
  p_room text,   -- rooms.id / messages.room_id bertipe TEXT (mis. 'Indonesia_general')
  p_uid  uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_private   boolean;
  v_country   text;
  v_min_days  integer;
  v_min_msgs  integer;
  v_created   timestamptz;
  v_msgs      integer;
begin
  if p_uid is null or p_room is null then
    return false;
  end if;

  select r.is_private, r.country
    into v_private, v_country
    from public.rooms r
   where r.id = p_room;

  if v_private is null then
    return false; -- room tidak ada
  end if;

  -- Room privat: perilaku lama, bebas.
  if v_private then
    return true;
  end if;

  -- Admin global & moderator negara room tsb: bypass.
  if public.is_chatyuk_admin(p_uid) then
    return true;
  end if;
  if public.is_country_moderator(v_country, p_uid) then
    return true;
  end if;

  select coalesce(media_trust_min_days, 3),
         coalesce(media_trust_min_msgs, 20)
    into v_min_days, v_min_msgs
    from public.app_settings where id = 'global';

  -- (1) umur akun
  select p.created_at into v_created
    from public.profiles p where p.id = p_uid;
  if v_created is null then
    return false;
  end if;
  if v_created > now() - make_interval(days => v_min_days) then
    return false;
  end if;

  -- (2) aktivitas: jumlah pesan di ROOM PUBLIK (bukan private chat)
  select count(*)
    into v_msgs
    from public.messages m
    join public.rooms r2 on r2.id = m.room_id
   where m.sender_id = p_uid
     and r2.is_private = false;

  return v_msgs >= v_min_msgs;
end;
$function$;

revoke execute on function public.can_send_room_media(text, uuid) from public, anon;
grant execute on function public.can_send_room_media(text, uuid) to authenticated, service_role;

-- ── 4. Rate limit media ────────────────────────────────────────────────────
create or replace function public.room_media_rate_ok(
  p_room text,   -- rooms.id / messages.room_id bertipe TEXT
  p_uid  uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_per_min  integer;
  v_per_hour integer;
  v_min_cnt  integer;
  v_hour_cnt integer;
begin
  select coalesce(media_rate_per_min, 3),
         coalesce(media_rate_per_hour, 20)
    into v_per_min, v_per_hour
    from public.app_settings where id = 'global';

  select count(*) filter (where m.created_at > now() - interval '1 minute'),
         count(*)
    into v_min_cnt, v_hour_cnt
    from public.messages m
   where m.room_id = p_room
     and m.sender_id = p_uid
     and public.is_room_media_type(m.type)
     and m.created_at > now() - interval '1 hour';

  return v_min_cnt < v_per_min and v_hour_cnt < v_per_hour;
end;
$function$;

revoke execute on function public.room_media_rate_ok(text, uuid) from public, anon;
grant execute on function public.room_media_rate_ok(text, uuid) to authenticated, service_role;

-- ── 5. Trigger penegak (server-side, tidak bisa dilewati klien) ────────────
create or replace function public.enforce_room_media_gate()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_private boolean;
begin
  if not public.is_room_media_type(new.type) then
    return new;
  end if;

  select r.is_private into v_private from public.rooms r where r.id = new.room_id;
  -- Room privat / grup privat: perilaku lama.
  if coalesce(v_private, false) then
    return new;
  end if;

  -- Admin request (service_role / email admin) tetap bebas (mis. migrasi data).
  if public.is_admin_request() then
    return new;
  end if;

  if not public.can_send_room_media(new.room_id, new.sender_id) then
    raise exception 'media_trust_gate' using errcode = '42501';
  end if;

  if not public.room_media_rate_ok(new.room_id, new.sender_id) then
    raise exception 'media_rate_limited' using errcode = '42901';
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_room_media_gate_trg on public.messages;
create trigger enforce_room_media_gate_trg
  before insert on public.messages
  for each row execute function public.enforce_room_media_gate();
