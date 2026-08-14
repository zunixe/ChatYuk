# Rencana Peningkatan Sistem Poin ChatYuk

Audit sistem poin: 3 bug (poin user hilang diam-diam) + peningkatan retensi
(login streak) + utang teknis string (melanggar AGENTS.md).

Keputusan pemilik produk:
1. Bonus chat orang baru: **harian ber-limit** (bukan one-time)
2. Bonus share: **beda channel beda nilai** (dipertahankan)

---

## BUG (prioritas tinggi — poin user hilang)

### A. Action key di luar whitelist → bonus SELALU gagal

RPC `one_time_bonus` whitelist (`points_v1.sql:141-143`):
`registered, rated_app, completed_profile, shared_app, first_photo,
first_room_chat, online_5min/30min/60min/120min`

Kode memanggil key yang TIDAK ada di whitelist → RPC
`raise exception 'Invalid action key'` → provider catch diam → user tidak
pernah dapat poin:

| Lokasi | Key dipanggil | Nilai | Status |
|---|---|---|---|
| `online_users_screen.dart:164` | `new_chat_${uid}` | +5 | tidak pernah masuk |
| `profile_screen.dart:514` | `invited_friend` | +30 | tidak pernah masuk |

Fix:
1. Tambah `invited_friend` ke whitelist.
2. `new_chat_*`: ganti ke RPC baru `new_chat_bonus(other_uid)` — harian
   ber-limit (keputusan #1). Key dinamis per-uid dihapus dari alur
   `one_time_bonus` karena tidak bisa di-whitelist.

Desain `new_chat_bonus(other_uid uuid)`:
- Kolom baru `profiles.new_chats_today int not null default 0`
- Guard 1 (anti-farming orang sama): cek `point_events` — kalau pasangan
  (user, other_uid) sudah pernah dapat bonus, tidak diberi lagi
- Guard 2 (limit harian): `new_chats_today < 3` → maks 3×/hari
- Award +5, increment counter, catat `point_events` metadata `{other_uid}`
- Counter direset di `daily_login_bonus`

Ini menutup dua lubang sekaligus: key ilegal + farming tanpa batas.

### Keputusan: beda channel beda nilai (share)

| Channel | Key | Nilai | Catatan |
|---|---|---|---|
| Tombol share di profil | `invited_friend` | +30 | perlu ditambah ke whitelist |
| Dialog out-of-points | `shared_app` | +10 | sudah di whitelist |

Konsekuensi yang **disengaja**: user bisa klaim keduanya (total +40) karena
dua-duanya one-time terpisah. Ini keputusan produk, bukan bug.

### B. Waktu online sesi pertama tidak terhitung

`_sessionStart` hanya di-set di branch `AppLifecycleState.resumed`
(`points_provider.dart:122`). Cold start tidak selalu memicu `resumed` →
sesi pertama tidak dihitung sampai app di-background lalu dibuka lagi.
Milestone `online_5min` dst under-counted.

Fix: set `_sessionStart` + mulai tick timer saat provider dibuat (registrasi
`WidgetsBindingObserver`), bukan hanya di `resumed`.

### C. RPC `get_points_enabled` hilang dari migration

`points_service.dart:10` memanggil `rpc('get_points_enabled')`, tapi RPC ini
tidak ada di file SQL manapun. Kemungkinan dibuat manual di DB (tidak
reproducible) atau memang hilang.

Fix: buat RPC-nya di migration (`create or replace`, aman kalau sudah ada di
DB) — baca `app_settings.points_enabled`.

---

## PENINGKATAN

### D. Login streak (retensi)

Sekarang daily login flat +25. Streak (hari berturut-turut) adalah pendorong
retensi terkuat untuk chat app.

Skema DB:
```sql
alter table public.profiles
  add column if not exists login_streak int not null default 0,
  add column if not exists last_login_date date;
```

Logika `daily_login_bonus()` (rewrite):
- Hitung selisih hari dari `last_login_date` (TZ `Asia/Jakarta`):
  - selisih `0` → sudah klaim hari ini, return points (idempotent)
  - selisih `1` → `login_streak += 1` (lanjut)
  - selisih `> 1` atau `null` → `login_streak = 1` (reset)
- Bonus bertingkat:

| Streak | Bonus |
|---|---|
| 1 | +25 |
| 2 | +30 |
| 3 | +35 |
| 4 | +40 |
| 5 | +45 |
| 6 | +50 |
| 7 | +100 (bonus mingguan) → siklus ulang ke 1 |

- Set `last_login_date = current_date`
- Reset: `room_reads_today = 0`, `new_chats_today = 0`, hapus one-time
  `online_5min/30min/60min/120min`
- Catat `point_events`: event `daily_login`, metadata `{streak, bonus}`

Client:
- `PointsProvider` tambah state `loginStreak` + getter
- Toast saat klaim: "🔥 Streak 3 hari — +35 Poin"
- Badge streak di profil (opsional, fase berikut)

**Catatan urutan migration:** A dan D dua-duanya menyentuh
`daily_login_bonus`. Supaya `create or replace` tidak saling menimpa,
dipecah 2 migration berurutan:
1. Migration 1 (A+C): kolom `new_chats_today`, whitelist `invited_friend`,
   RPC `new_chat_bonus`, RPC `get_points_enabled`
2. Migration 2 (D): rewrite `daily_login_bonus` dengan streak **plus**
   semua reset (termasuk `new_chats_today` dari migration 1)

### G. Rapikan string poin ke strings.dart (WAJIB per AGENTS.md)

**G1. Mojibake pada getter yang DIPAKAI**
- `pointsSafe` = `'? Aman selamanya'` (emoji ✅ rusak) — tampil ke user di
  `profile_screen.dart:740`
- Komentar `// ?? Points ??` di `strings.dart:298` juga rusak

**G2. String poin inline hardcode** (melanggar "semua string lewat `s.`")

| File | Baris | String |
|---|---|---|
| `private_chat_screen.dart` | 322 | `-1 Poin` / `-1 Point` |
| `private_chat_screen.dart` | 376, 453 | `-3 Poin` / `-3 Points` |
| `private_chat_screen.dart` | 379 | `+10 Poin — Foto pertama!` |
| `room_chat_screen.dart` | 64 | `+2 Poin — Baca room` |
| `room_chat_screen.dart` | 135 | `-1 Poin` |
| `room_chat_screen.dart` | 142 | `+5 Poin — Room chat!` |
| `profile_screen.dart` | 447 | `+10 Poin — Profil lengkap!` |
| `profile_screen.dart` | 516 | `+30 Poin — Share!` |
| `link_email_screen.dart` | 51 | `+100 Poin!` |
| `points_provider.dart` | 78-90 | seluruh teks onboarding |
| `points_provider.dart` | 180-192 | label toast online |
| `points_provider.dart` | 293-342 | seluruh dialog out-of-points |

**G3. 16 getter MATI** (tidak ada satu pun call site) → hapus:
`pointsEstimate, pointsSecureHeader, pointsSecureBody, pointsLow,
pointsEmptyTitle, pointsDailyLoginTxt, pointsOnlineBonus, pointsRateAppLabel,
pointsShareAppLabel, pointsInviteLabel, pointsProfileLabel, pointsNewChatLabel,
pointsFirstPhotoLabel, pointsRegisterBonusText, pointsDeductToast, pointsEarned`

Getter ini pakai format `%d`/`%s` yang tidak didukung Dart — dihapus, bukan
diperbaiki.

**Rancangan getter baru** (parameter via fungsi, bukan `%d`):
```dart
String pointsDeduct(int n)              // '-$n Poin' / '-$n Points'
String pointsGain(int n, String reason) // '+$n Poin — $reason'
String pointsStreak(int day, int n)     // '🔥 Streak $day hari — +$n Poin'
```
Plus getter alasan: `reasonFirstPhoto`, `reasonRoomRead`, `reasonRoomChat`,
`reasonProfileComplete`, `reasonShare`, `reasonNewChat`, `reasonRegister`,
`reasonRateApp`, `reasonOnline5/30/60/120`.

Onboarding & dialog out-of-points: setiap baris dipindah ke getter bilingual.

Aturan setelah refactor: **tidak boleh ada** string `'...Poin...'` hardcode
di `lib/screens/` dan `lib/providers/`.

---

## BACKLOG (di luar scope sekarang)

- **E. Leaderboard mingguan** dari `point_events`. `admin_stats.top_earners`
  sudah menghitungnya untuk admin — bisa diangkat jadi fitur user-facing.
- **F. Rate app asli.** Dialog "Rate ChatYuk" memberi +20 tanpa benar-benar
  membuka Play Store (`points_provider.dart:308`) — user klaim bonus tanpa
  rate. Perlu `in_app_review` / `launchUrl`.

---

## Urutan eksekusi

1. **C** — RPC `get_points_enabled` (fondasi, cepat)
2. **A** — whitelist `invited_friend` + RPC `new_chat_bonus` + kolom
3. **B** — fix tracking online sesi pertama
4. **D** — login streak (migration 2 + provider + toast)
5. **G** — refactor string (terakhir; menyentuh file yang sama dengan A/B/D)
6. `flutter analyze` → harus 0 error / 0 warning
7. `supabase db push` (migration 1 & 2) + verifikasi RPC di dashboard
8. Build release:
   ```bash
   KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
     flutter build apk --release --obfuscate --split-debug-info=build/app/symbols
   ```
9. Install & test di HP

## Verifikasi

- [ ] `flutter analyze` bersih (0 error, 0 warning)
- [ ] Grep: tidak ada `'Poin'`/`'Point'` hardcode di `lib/screens/`, `lib/providers/`
- [ ] Chat orang baru → +5 masuk (maks 3×/hari, tidak dobel utk orang sama)
- [ ] Share dari profil → +30 masuk
- [ ] Share dari dialog out-of-points → +10 masuk
- [ ] Online 5 menit pada sesi pertama (tanpa background) → +5 masuk
- [ ] Login besok → streak naik, bonus sesuai tabel
- [ ] Mojibake `✅ Aman selamanya` tampil benar di profil
