# ChatYuk Monetization & Poin System Plan

---

## 1. Konsep

Poin adalah **bahan bakar chat** — dikonsumsi tiap kirim pesan. Bukan reward, tapi resource.

- **Anonymous:** Poin bisa hangus saat logout / uninstall / ganti HP
- **Registered:** Poin aman selamanya

---

## 2. Aturan Poin

### 2.1 Poin Berkurang

| Aksi | Poin |
|------|:---:|
| Kirim chat teks (private) | -1 |
| Kirim chat teks (room) | -1 |
| Kirim foto | -3 |
| Kirim view-once photo | -3 |

Tidak mengurangi: menerima pesan, membaca, buka app, lihat user.

### 2.2 Passive Income (Auto, Harian)

| Sumber | Poin |
|--------|:---:|
| Login harian | +25 |
| Online 5 menit | +5 |
| Online 30 menit | +10 |
| Online 60 menit | +15 |
| Online 120 menit | +15 |
| Baca room chat ×5 | +10 |
| **Total** | **+80** |

### 2.3 One-Time Actions (Menguntungkan App)

| Aksi | Poin | Benefit ke App |
|------|:---:|------|
| 📧 Register email | +100 | Konversi, retensi |
| ⭐ Rate app di Play Store | +20 | Ranking, organic install |
| 📢 Share app ke sosmed/WA | +10 | Virality |
| 👥 Invite teman install | +30/orang | User acquisition |
| 📝 Lengkapi profil | +10 | Data matching |
| 👤 Chat orang baru | +5/orang | Network density |
| 📸 Kirim foto pertama | +10 | Feature discovery |
| 💬 Room chat 5 pesan | +5 | Room jadi ramai |

Action verification:
- ⭐ Rate & 📢 Share: trust client (trade-off, poin kecil, tidak worth untuk cheat)
- 📝 Lengkapi profil: cek field DB (age ≠ 0, country ≠ '', city ≠ '', hashtags ≥ 1)
- 👤 Chat orang baru: tracking di `one_time_actions` + query `private_chats`
- 📸 Kirim foto pertama: cek `one_time_actions`

---

## 3. Simulasi

### 3.1 Daily Balance

| User | Pesan/hari | Poin dipakai | Income | Saldo/hari |
|------|:---:|:---:|:---:|---|
| Casual | 5 | -5 | +80 | ✅ +75 |
| Normal | 20 | -20 | +80 | ✅ +60 |
| Ngobrol 1 orang | 50 | -50 | +80 | ✅ +30 |
| Serius | 80 | -80 | +80 | ✅ 0 (break-even) |
| Power | 100 | -100 | +80 | ⚠️ -20 |
| Super power | 150 | -150 | +80 | ⚠️ -70 |

### 3.2 Saat Kehabisan Hari Ini

| Action | Poin |
|--------|:---:|
| ⭐ Rate app | 20 |
| 📝 Lengkapi profil | 10 |
| 📢 Share app | 10 |
| 👤 Chat 3 orang baru | 15 |
| 📸 Kirim foto pertama | 10 |
| 💬 Room chat 5x | 5 |
| 📖 Baca room 5x | 10 |
| **Total** | **80** |

80 poin = bisa chat 80× lagi, cukup sampai besok.

### 3.3 Kesimpulan

| Volume chat | Tanpa register | Dengan register (+100) |
|-------------|:---:|:---:|
| ≤80 msg/hari | ✅ Selamanya gratis | ✅ Sangat aman |
| 100 msg/hari | ⚠️ Butuh action 1-2×/minggu | ✅ Aman 3 minggu |
| 150+ msg/hari | ❌ Harus register + action | ⚠️ Sesekali butuh action |

**≤80 pesan/hari = gratis selamanya, cukup login aja.** Power user perlu register — itupun ringan karena +100 bonus.

---

## 4. Start Poin

| Kondisi | Poin |
|---------|:---:|
| User baru | 50 |

---

## 5. Flow UX

### 5.1 Graduated Warning

```
Normal (≥21)  → tidak ada badge
Rendah (≤20)  → badge hijau "20 poin"
Kritis (≤10)  → badge kuning "10 poin — baca room +2"
Habis (≤5)    → badge oranye "⚠️ 5 poin — daftar email +100"
Kosong (=0)   → dialog penuh
```

### 5.2 Badge Peringatan di Input Bar

```
┌──────────────────────────────────────────┐
│  ⚠️ 3 poin  [input................]  [📤] │
└──────────────────────────────────────────┘
```

### 5.3 Poin Counter di Chat Screen

Poin counter kecil di AppBar subtitle — selalu visible, tidak hanya saat rendah.

```
AppBar:
  Nama User                          🪙 250
  subtitle | online
```

### 5.4 Estimasi di Profile

"250 poin ≈ 250 pesan lagi" (poin/1).

### 5.5 Dialog Poin Habis (0)

```
┌─────────────────────────────────────────┐
│  😢 Poin kamu habis!                   │
│                                         │
│  ⚠️ Akun anonim: poin bisa hilang      │
│  kapan saja!                            │
│                                         │
│  Dapatkan sekarang:                     │
│  📧 Daftar Email           +100        │
│  ⭐ Rate ChatYuk            +20        │
│  👥 Invite teman            +30        │
│  📢 Share ke teman          +10        │
│  📝 Lengkapi profil         +10        │
│  👤 Chat orang baru          +5        │
│  📸 Kirim foto pertama      +10        │
│                                         │
│  Atau gratis besok:                     │
│  📅 Login besok             +25        │
│  📖 Baca room                +2        │
│                                         │
│                          [Tutup]        │
└─────────────────────────────────────────┘
```

### 5.6 Toast Feedback

Setiap kali dapat poin: toast slide-up kecil "+X Poin — [reason]" (fade 1.5 detik).

Daftar toast:
- `+25 Poin — Login harian`
- `+5 Poin — Online 5 menit`
- `+10 Poin — Online 30 menit`
- `+15 Poin — Online 60 menit`
- `+15 Poin — Online 120 menit`
- `+2 Poin — Baca room`
- `+100 Poin — Register email!`
- `+20 Poin — Rate app`
- `+10 Poin — Share app`
- `+5 Poin — Chat orang baru`
- `-1 Poin` (setelah kirim pesan)

### 5.7 Onboarding Dialog

Saat first install / setelah entry screen, 1× dialog singkat:

```
┌─────────────────────────────────┐
│  🪙 Sistem Poin ChatYuk         │
│                                  │
│  Chat = pakai poin.              │
│  Login tiap hari = +25 poin.    │
│  Online 60 menit = +45 bonus.   │
│  Daftar email = +100 + AMAN!    │
│                                  │
│  🎉 Mulai dengan 50 poin gratis │
│                                  │
│                      [OK, Paham] │
└─────────────────────────────────┘
```

---

## 6. Tampilan Poin

### 6.1 Profile — Anonymous

```
┌────────────────────────────────┐
│  🔒 15 Poin                    │
│  ⚠️ Poin bisa hilang kalau     │
│  logout atau ganti HP           │
│                                 │
│  📧 Daftar Email +100 Poin     │
│  [Amankan Akun]                │
└────────────────────────────────┘
```

### 6.2 Profile — Registered

```
┌────────────────────────────────┐
│  🪙 250 Poin                   │
│  ≈ 250 pesan lagi              │
│  +25 login besok               │
│  +55 online bonus              │
│  ✅ Aman selamanya             │
└────────────────────────────────┘
```

### 6.3 LinkEmailScreen

```
┌─────────────────────────────────┐
│  🔒 Amankan Poin Kamu           │
│                                  │
│  Kamu punya 250 poin.            │
│  Daftar email = poin aman       │
│  selamanya + bonus 100!          │
│                                  │
│  [Email........................] │
│  [Password....................]  │
│  [Konfirmasi..................]  │
│  [Daftar]                       │
└─────────────────────────────────┘
```

---

## 7. DB Schema

### 7.1 Kolom Baru

```sql
alter table public.profiles
  add column if not exists points int not null default 50,
  add column if not exists one_time_actions jsonb not null default '{}',
  add column if not exists room_reads_today int not null default 0;

alter table public.app_settings
  add column if not exists points_enabled boolean not null default true;

-- Analytics tracking
create table if not exists public.point_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade,
  event text not null,
  amount int not null default 0,
  metadata jsonb default '{}',
  created_at timestamptz not null default now()
);
create index if not exists idx_point_events_user on public.point_events(user_id, created_at);
create index if not exists idx_point_events_event on public.point_events(event, created_at);
```

**one_time_actions keys:**
- Harian (reset tiap login): `online_5min`, `online_30min`, `online_60min`, `online_120min`
- One-time (tidak pernah reset): `registered`, `rated_app`, `completed_profile`, `shared_app`, `first_photo`, `first_room_chat`

### 7.2 RPC: Daily Login Bonus

```sql
create or replace function public.daily_login_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare r int;
begin
  if exists (select 1 from profiles
             where id = auth.uid()
             and login_at >= current_date at time zone 'Asia/Jakarta')
  then
    select points from profiles where id = auth.uid() into r;
    return r;
  end if;

  update profiles set
    points = points + 25,
    login_at = now(),
    room_reads_today = 0,
    one_time_actions = one_time_actions - array[
      'online_5min','online_30min','online_60min','online_120min'
    ]
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount)
    values (auth.uid(), 'daily_login', 25);

  return r;
end;
$$;

revoke execute on function public.daily_login_bonus() from public, anon;
grant execute on function public.daily_login_bonus() to authenticated, service_role;
```

### 7.3 RPC: Deduct Chat Point (Atomic — Dipanggil Sebelum Insert)

```sql
create or replace function public.deduct_chat_point(msg_type text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  points_enabled_val boolean;
  cost int;
  remaining int;
begin
  -- Feature flag check
  select app_settings.points_enabled into points_enabled_val
    from app_settings where id = 'global';
  if points_enabled_val is false then
    select points from profiles where id = auth.uid() into remaining;
    return coalesce(remaining, 0);
  end if;

  cost := case msg_type
    when 'image' then 3
    when 'view_once' then 3
    when 'view_once_expired' then 0
    else 1
  end;

  update profiles
  set points = points - cost
  where id = auth.uid()
  returning points into remaining;

  if remaining < 0 then
    update profiles set points = points + cost where id = auth.uid();
    raise exception 'Not enough points';
  end if;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'deduct', -cost, jsonb_build_object('msg_type', msg_type));

  return remaining;
end;
$$;

grant execute on function public.deduct_chat_point(text) to authenticated, service_role;
```

### 7.4 RPC: Room Read Bonus (5×/hari)

```sql
create or replace function public.room_read_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare r int;
begin
  update profiles
  set points = points + 2, room_reads_today = room_reads_today + 1
  where id = auth.uid() and room_reads_today < 5
  returning points into r;

  if found then
    insert into point_events (user_id, event, amount)
      values (auth.uid(), 'room_read', 2);
  end if;

  return coalesce(r, (select points from profiles where id = auth.uid()));
end;
$$;

grant execute on function public.room_read_bonus() to authenticated, service_role;
```

### 7.5 RPC: One-Time Action Bonus

```sql
create or replace function public.one_time_bonus(action_key text, bonus int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  valid_actions text[];
  r int;
begin
  -- Whitelist action key
  valid_actions := array['registered','rated_app','completed_profile',
    'shared_app','first_photo','first_room_chat',
    'online_5min','online_30min','online_60min','online_120min'];

  if not (action_key = any(valid_actions)) then
    raise exception 'Invalid action key: %', action_key;
  end if;

  if exists (select 1 from profiles
             where id = auth.uid()
             and one_time_actions->>action_key = 'true')
  then
    select points from profiles where id = auth.uid() into r;
    return r;
  end if;

  update profiles
  set points = points + bonus,
      one_time_actions = one_time_actions || jsonb_build_object(action_key, true)
  where id = auth.uid()
  returning points into r;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'bonus', bonus, jsonb_build_object('action', action_key));

  return r;
end;
$$;

grant execute on function public.one_time_bonus(text, int) to authenticated, service_role;
```

### 7.6 RPC: Register Bonus

```sql
create or replace function public.register_bonus()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.one_time_bonus('registered', 100);
end;
$$;

grant execute on function public.register_bonus() to authenticated, service_role;
```

### 7.7 RPC: New Chat Bonus

```sql
create or replace function public.new_chat_bonus(target_uid text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  chat_id_val text;
  r int;
begin
  -- Hitung chat dengan orang baru (kedua arah)
  chat_id_val := (
    select chat_id from private_chats
    where exists (
      select 1 from unnest(participants) as p where p = auth.uid()
    )
    and exists (
      select 1 from unnest(participants) as p where p::text = target_uid
    )
    limit 1
  );

  if chat_id_val is null then
    select points from profiles where id = auth.uid() into r;
    return r;
  end if;

  update profiles
  set points = points + 5
  where id = auth.uid()
  and not (one_time_actions->('new_chat_' || target_uid) is not null)
  returning points into r;

  if found then
    update profiles
    set one_time_actions = one_time_actions ||
      jsonb_build_object('new_chat_' || target_uid, true)
    where id = auth.uid();

    insert into point_events (user_id, event, amount, metadata)
      values (auth.uid(), 'bonus', 5, jsonb_build_object('action', 'new_chat', 'with_uid', target_uid));
  end if;

  return coalesce(r, (select points from profiles where id = auth.uid()));
end;
$$;

grant execute on function public.new_chat_bonus(text) to authenticated, service_role;
```

### 7.8 admin_stats (admin only)

```sql
create or replace function public.admin_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total_users', (select count(*) from profiles),
    'active_today', (select count(*) from profiles
      where last_seen >= current_date at time zone 'Asia/Jakarta'),
    'registered_users', (select count(*) from profiles where is_registered = true),
    'anonymous_users', (select count(*) from profiles where is_registered = false),
    'messages_today',
      (select count(*) from private_messages where created_at >= current_date at time zone 'Asia/Jakarta') +
      (select count(*) from messages where created_at >= current_date at time zone 'Asia/Jakarta'),
    'rooms_active', (select count(distinct room_id) from room_presence where left_at is null),
    'avg_points', (select round(avg(points)) from profiles),
    'total_points', (select sum(points) from profiles),
    'top_earners', (select jsonb_agg(
      jsonb_build_object('nickname', nickname, 'points', points, 'uid', id)
      order by points desc) from (select id, nickname, points from profiles order by points desc limit 10) t),
    'stuck_users', (select count(*) from profiles
      where points = 0 and last_seen >= (now() - interval '7 days')),
    'reported_users', (select coalesce(jsonb_agg(
      jsonb_build_object('reported_id', reported_id, 'report_count', c)
      order by c desc), '[]'::jsonb)
      from (select reported_id, count(*) as c from reports
            group by reported_id order by c desc limit 20) sub),
    'points_enabled', (select points_enabled from app_settings where id = 'global')
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_stats() to authenticated, service_role;
```

### 7.9 admin_mass_bonus (admin only)

```sql
create or replace function public.admin_mass_bonus(bonus int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  affected int;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update profiles set points = points + bonus where is_registered = true;
  get diagnostics affected = row_count;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_mass_bonus', bonus,
            jsonb_build_object('affected_users', affected));

  return jsonb_build_object('affected', affected, 'bonus', bonus);
end;
$$;

grant execute on function public.admin_mass_bonus(int) to authenticated, service_role;
```

### 7.10 admin_reset_points (admin only)

```sql
create or replace function public.admin_reset_points()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare affected int;
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update profiles set points = 50;
  get diagnostics affected = row_count;

  insert into point_events (user_id, event, amount, metadata)
    values (auth.uid(), 'admin_reset_all', 0,
            jsonb_build_object('affected_users', affected));

  return affected;
end;
$$;

grant execute on function public.admin_reset_points() to authenticated, service_role;
```

### 7.11 admin_toggle_points (admin only)

```sql
create or replace function public.admin_toggle_points(enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.email() != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  update app_settings
  set points_enabled = enabled, updated_at = now()
  where id = 'global';

  return enabled;
end;
$$;

grant execute on function public.admin_toggle_points(boolean) to authenticated, service_role;
```

---

## 8. Admin Panel (`zunixe@gmail.com` only)

### 8.1 Entry Point

Profile Screen → Settings section → "Admin Panel" row (hanya untuk `zunixe@gmail.com`) → tap → push `AdminPanelScreen`.

### 8.2 Admin Panel Screen Layout

```
┌──────────────────────────────────┐
│ ← Admin Panel                    │
├──────────────────────────────────┤
│                                  │
│  📊 STATISTIK                    │
│  ┌──────────┬──────────┐         │
│  │ 1,250    │  340     │         │
│  │ Total    │ Aktif    │         │
│  │ Users    │ Hari Ini │         │
│  ├──────────┼──────────┤         │
│  │ 890      │  12      │         │
│  │ Regis-   │ Room     │         │
│  │ tered    │ Aktif    │         │
│  ├──────────┼──────────┤         │
│  │ 2,890    │  480     │         │
│  │ Pesan    │ Rata²    │         │
│  │ Hari Ini │ Poin     │         │
│  └──────────┴──────────┘         │
│                                  │
│  🪙 POIN MONITORING              │
│  ┌──────────────────────┐        │
│  │ #1 @user1    2,450   │        │
│  │ #2 @user2    1,890   │        │
│  │ #3 @user3    1,340   │        │
│  │ #4 @user4      980   │        │
│  │ #5 @user5      860   │        │
│  └──────────────────────┘        │
│  8 user stuck (0 poin)          │
│  [Lihat →]                       │
│  Total poin beredar: 125,000    │
│                                  │
│  ⚙️ CONTROL                      │
│  ┌──────────────────────┐        │
│  │ 🟢 Sistem Poin    [✓] │        │
│  │ 📸 Screenshot     [✓] │        │
│  │ 🔏 Watermark      [✓] │        │
│  └──────────────────────┘        │
│                                  │
│  🎁 MASS BONUS                   │
│  ┌──────────────────────┐        │
│  │ [  +100   ] [Kirim]  │        │
│  │ ⚠️ Kasih ke semua    │        │
│  │ user registered       │        │
│  └──────────────────────┘        │
│                                  │
│  📋 REPORTED USERS (Top 20)      │
│  @spammer1 — 3 reports          │
│  @abuser2  — 2 reports          │
│  [Lihat Semua →]                 │
│                                  │
│  🔐 FORCE LOGOUT                 │
│  [User ID:_______] [Logout]      │
│                                  │
│  ⚠️ DANGER ZONE                  │
│  [Reset Semua Poin]              │
│  ⚠️ Semua user jadi 50 poin     │
└──────────────────────────────────┘
```

### 8.3 Fitur Admin Panel

| Fitur | Fungsi | RPC/Query |
|-------|--------|-----------|
| Stats cards (6 cards) | Total users, active today, registered, active rooms, messages today, avg points | `admin_stats()` |
| Top earners (top 5) | User dengan poin tertinggi | Dari `admin_stats().top_earners` |
| Stuck users count | User dengan 0 poin (7 hari terakhir) | Dari `admin_stats().stuck_users` |
| Poin system toggle | Enable/disable global (kalau off, RPC no-op) | `admin_toggle_points()` |
| Screenshot toggle | (existing) | (existing) |
| Watermark toggle | (existing) | (existing) |
| Mass bonus | Input amount + kirim ke semua user registered | `admin_mass_bonus(amount)` |
| Reported users | Top 20 user yang direport | Dari `admin_stats().reported_users` |
| Force logout | Hapus FCM token user target | Direct update profiles |
| Reset all points | Kembalikan semua ke 50 | `admin_reset_points()` |

### 8.4 File Baru

| File | Fungsi |
|------|--------|
| `lib/screens/admin_panel_screen.dart` | Full admin dashboard UI |
| `lib/services/admin_service.dart` | Panggil semua admin RPC |
| `lib/providers/admin_provider.dart` | State admin: stats, loading |

---

## 9. File Yang Dikerjakan

| File | Perubahan |
|------|-----------|
| `supabase/migrations/points_v1.sql` | **BARU** — ALTER profiles, point_events, app_settings, 11 RPC |
| `lib/models/user_model.dart` | +`points`, `oneTimeActions`, `roomReadsToday` |
| `lib/services/auth_service.dart` | `getProfile()` +points cols; `dailyLoginBonus()` call |
| `lib/services/chat_service.dart` | `deductChatPoint()` sebelum insert di `sendRoomMessage` & `sendPrivateMessage` |
| `lib/services/points_service.dart` | **BARU** — online tracker, room read, one-time actions, toast feedback |
| `lib/services/admin_service.dart` | **BARU** — admin stats, mass bonus, wipe, force logout |
| `lib/providers/points_provider.dart` | **BARU** — state poin, dialog habis, graduated warning, onboarding |
| `lib/providers/admin_provider.dart` | **BARU** — admin state, toggle, stats |
| `lib/providers/auth_provider.dart` | `linkEmailToAccount` → `registerBonus()`; profile update → `oneTimeBonus('completed_profile')` |
| `lib/screens/profile_screen.dart` | Poin display + badge + estimasi + CTA + admin entry |
| `lib/screens/private_chat_screen.dart` | Badge peringatan poin rendah; dialog poin habis; toast "-1 Poin"; poin di AppBar |
| `lib/screens/room_chat_screen.dart` | Badge peringatan; toast "-1 Poin"; room read bonus trigger |
| `lib/screens/link_email_screen.dart` | Header bonus poin + teaser |
| `lib/screens/admin_panel_screen.dart` | **BARU** — full admin dashboard |
| `lib/config/strings.dart` | ±50 string bilingual |

---

## 10. String Bilingual

```dart
// ── Points ──
String get pointsTitle              => isId ? 'Poin ChatYuk'                   : 'ChatYuk Points';
String get pointsBalance            => isId ? 'Poin'                           : 'Points';
String get pointsEstimate           => isId ? '≈ %d pesan lagi'                : '≈ %d more messages';
String get pointsEmptyTitle         => isId ? 'Poin Habis!'                    : 'Out of Points!';
String get pointsEmptyBody          => isId ? 'Dapatkan poin sekarang atau tunggu login besok.' : 'Get points now or wait for tomorrow.';
String get pointsAnonymousLose      => isId ? 'Poin akan hilang kalau kamu logout atau ganti HP' : 'Points will be lost if you logout or switch phones';
String get pointsSecureHeader       => isId ? 'Amankan Poin Kamu'              : 'Secure Your Points';
String get pointsSecureBody         => isId ? '%d poin. Daftar = aman + bonus 100!' : '%d points. Register = safe + 100 bonus!';
String get pointsLow                => isId ? '⚠️ %d poin'                      : '⚠️ %d points';
String get pointsSafe               => isId ? '✅ Aman selamanya'               : '✅ Safe forever';

// ── Passive Income ──
String get pointsDailyLogin         => isId ? '+25 login harian'              : '+25 daily login';
String get pointsOnline5            => isId ? '+5 online 5 menit'              : '+5 online 5 min';
String get pointsOnline30           => isId ? '+10 online 30 menit'             : '+10 online 30 min';
String get pointsOnline60           => isId ? '+15 online 60 menit'             : '+15 online 60 min';
String get pointsOnline120          => isId ? '+15 online 120 menit'            : '+15 online 120 min';
String get pointsRoomRead           => isId ? '+2 baca room'                   : '+2 room read';

// ── One-Time Actions ──
String get pointsRegisterBonus      => isId ? '+100 daftar email'              : '+100 register email';
String get pointsRateApp            => isId ? '+20 rate aplikasi'              : '+20 rate app';
String get pointsShareApp           => isId ? '+10 share ke teman'              : '+10 share app';
String get pointsInviteFriend       => isId ? '+30 invite teman'               : '+30 invite friend';
String get pointsCompleteProfile    => isId ? '+10 lengkapi profil'             : '+10 complete profile';
String get pointsNewChat            => isId ? '+5 chat orang baru'              : '+5 chat new person';
String get pointsFirstPhoto         => isId ? '+10 kirim foto pertama'          : '+10 first photo';
String get pointsRoomChat           => isId ? '+5 chat di room'                 : '+5 room chat';

// ── Feedback ──
String get pointsEarned             => isId ? '+%d Poin'                       : '+%d Points';
String get pointsDeducted           => isId ? '-%d Poin'                       : '-%d Points';
String get pointsToastLogin         => isId ? 'Login harian'                   : 'Daily login';
String get pointsToastOnline5       => isId ? 'Online 5 menit'                  : 'Online 5 min';
String get pointsToastOnline30      => isId ? 'Online 30 menit'                 : 'Online 30 min';
String get pointsToastOnline60      => isId ? 'Online 60 menit'                 : 'Online 60 min';
String get pointsToastOnline120     => isId ? 'Online 120 menit'                : 'Online 120 min';
String get pointsToastRoomRead      => isId ? 'Baca room'                      : 'Room read';
String get pointsToastRegister      => isId ? 'Register email!'                : 'Register email!';
String get pointsToastRateApp       => isId ? 'Rate app'                       : 'Rate app';
String get pointsToastShareApp      => isId ? 'Share app'                      : 'Share app';
String get pointsToastNewChat       => isId ? 'Chat orang baru'                : 'New chat';
String get pointsToastSent          => isId ? 'Pesan terkirim'                 : 'Message sent';

// ── Onboarding ──
String get pointsOnboardingTitle    => isId ? 'Sistem Poin ChatYuk'            : 'ChatYuk Points System';
String get pointsOnboardingBody     => isId ? 'Chat = pakai poin.\nLogin tiap hari = +25 poin.\nOnline 60 menit = +45 bonus.\nDaftar email = +100 + AMAN!\n\n🎉 Mulai dengan 50 poin gratis' : 'Chat = uses points.\nDaily login = +25 points.\nOnline 60 min = +45 bonus.\nRegister email = +100 + SAFE!\n\n🎉 Start with 50 free points';
String get pointsOnboardingOk       => isId ? 'OK, Paham'                      : 'OK, Got it';

// ── Admin Panel ──
String get adminTitle               => 'Admin Panel';
String get adminSectionStats        => isId ? '📊 Statistik'                   : '📊 Statistics';
String get adminStatsTotalUsers     => isId ? 'Total User'                    : 'Total Users';
String get adminStatsActiveToday    => isId ? 'Aktif Hari Ini'                : 'Active Today';
String get adminStatsRegistered     => isId ? 'Registered'                    : 'Registered';
String get adminStatsAnonymous      => isId ? 'Anonymous'                     : 'Anonymous';
String get adminStatsMessagesToday  => isId ? 'Pesan Hari Ini'                : 'Messages Today';
String get adminStatsRoomsActive    => isId ? 'Room Aktif'                    : 'Active Rooms';
String get adminStatsAvgPoints      => isId ? 'Rata² Poin'                    : 'Avg Points';
String get adminSectionPoints       => isId ? '🪙 Poin Monitoring'            : '🪙 Points Monitoring';
String get adminTopEarners          => isId ? 'Top Poin'                      : 'Top Earners';
String get adminStuckUsers          => isId ? 'user kehabisan poin'           : 'users out of points';
String get adminTotalPoints         => isId ? 'Total poin beredar'            : 'Total points in circulation';
String get adminSectionControl      => isId ? '⚙️ Control'                    : '⚙️ Control';
String get adminPoinToggle          => isId ? 'Sistem Poin'                   : 'Points System';
String get adminScreenshotToggle    => isId ? 'Screenshot'                    : 'Screenshot';
String get adminWatermarkToggle     => isId ? 'Watermark'                     : 'Watermark';
String get adminSectionMassBonus    => isId ? '🎁 Bonus Massal'               : '🎁 Mass Bonus';
String get adminMassBonusDesc       => isId ? '⚠️ Akan kasih %d poin ke semua user registered.' : '⚠️ Will give %d points to all registered users.';
String get adminMassBonusBtn        => isId ? 'Kirim'                         : 'Send';
String get adminSectionReports      => isId ? '📋 User Dilaporkan'            : '📋 Reported Users';
String get adminReportCount         => isId ? '%d laporan'                    : '%d reports';
String get adminSeeAll              => isId ? 'Lihat Semua →'                  : 'See All →';
String get adminSectionForceLogout  => isId ? '🔐 Force Logout'               : '🔐 Force Logout';
String get adminForceLogoutBtn      => isId ? 'Logout'                        : 'Logout';
String get adminForceLogoutHint     => isId ? 'User ID'                       : 'User ID';
String get adminSectionDanger       => isId ? '⚠️ Danger Zone'                : '⚠️ Danger Zone';
String get adminWipePoints          => isId ? 'Reset Semua Poin'              : 'Wipe All Points';
String get adminWipePointsDesc      => isId ? '⚠️ Semua user kembali ke 50 poin' : '⚠️ All users reset to 50 points';
String get adminWipeConfirm         => isId ? 'Yakin reset semua poin ke 50?' : 'Sure to reset all points to 50?';
```

---

## 11. Estimasi Development

| Komponen | Waktu |
|----------|:---:|
| DB migration + 11 RPC | 1.5 jam |
| UserModel + auth service | 30 mnt |
| PointsService (online timer, room, actions) | 1 jam |
| AdminService (stats, bonus, wipe) | 45 mnt |
| ChatService (deduct point) | 30 mnt |
| PointsProvider (state, dialog, badges, onboarding) | 1 jam |
| AdminProvider | 30 mnt |
| AuthProvider (register bonus, profile bonus) | 20 mnt |
| Profile screen UI | 45 mnt |
| Admin Panel screen UI | 1.5 jam |
| Private chat screen (badge, dialog, toast, AppBar poin) | 45 mnt |
| Room chat screen (badge, toast, room read trigger) | 20 mnt |
| LinkEmail teaser | 15 mnt |
| Onboarding dialog | 20 mnt |
| Strings (50+ entries) | 30 mnt |
| Build + test + install | 30 mnt |
| **Total** | **±10 jam** |

---

## 12. Transisi Ke Topup (Future)

Saat topup live nanti:
- Tambah `yukcoins` table + `coin_transactions`
- `topup_yukcoin` RPC (Google Play IAP → credit)
- 1 YukCoin = 2 Poin
- Paket topup: 50/100/300 YukCoin
- Poin untuk chat, YukCoin untuk marketplace (stiker, premium) — DUA sistem terpisah

**Sistem poin sekarang tidak perlu diubah sama sekali.**
