# Insiden: `cleanup_stale_anonymous` menghapus user anon AKTIF (mass delete 1671) + `admin_list_deleted` abaikan limit (2026-10-02)

## Gejala
- Admin membuka tab **Terhapus** di panel admin: jumlahnya "banyak banget
  sampai 1781" dalam waktu singkat.
- Awalnya diduga sekadar masalah tampilan (chip menghitung dari baris yang
  ter-load). Investigasi ke DB justru menemukan **dua bug yang sama-sama
  aktif di produksi**, salah satunya destruktif.

## Data produksi saat investigasi (via Management API)
```sql
select reason, count(*), count(*) filter (where is_registered) as registered
  from public.deleted_users group by reason order by 2 desc;
```
| reason | n | registered | anon |
|---|---|---|---|
| `stale_cleanup` | **1671** | 0 | 1671 |
| `admin_delete` | 87 | 2 | 85 |
| `self_delete` | 18 | 7 | 11 |
| `nickname_claim` | 6 | 0 | 6 |

- Dari 1671 `stale_cleanup`: **1646 (98,5%) `last_seen_at` NULL**.

## Akar masalah 1 — `cleanup_stale_anonymous` FAIL-OPEN (destruktif)
Kondisi seleksi lama:
```sql
and not exists (
  select 1 from public.profiles p
  where p.id = u.id
    and p.last_seen > now() - make_interval(days => min_age_days)
)
```
Ini berarti "user yang **tidak punya** baris profil dengan `last_seen` baru":
- **(a)** user yang baris `profiles`-nya tidak ada → langsung lolos → dihapus
  meski statusnya tidak diketahui;
- **(b)** `last_seen IS NULL` → predikat `NULL > ts` = `NULL` (bukan true) →
  `NOT EXISTS` bernilai true → **lolos → dihapus padahal tidak ada bukti
  sama sekali bahwa ia inactive.**

Pola `NOT EXISTS(<predikat positif>)` = **fail-open**: ketiadaan data
diperlakukan sebagai bukti. Untuk operasi destruktif, ini salah total.

Cron `jobid 1` (`0 4 * * *`) menjalankannya **setiap hari 04:00**.

**Dampak terukur:** saat fix dipasang, ada 105 akun anon aktif dan hanya 6
yang berumur >7 hari. Aturan lama akan menghapus hampir **seluruh 105 akun
anon aktif** (termasuk yang sedang online) pada setiap run.

## Perbaikan 1 — fail-safe (migrasi `20261002000000`)
Hapus **hanya bila ada bukti umur** ≥ `min_age_days`:
```sql
and coalesce(p.last_seen, p.created_at, u.created_at) is not null
and coalesce(p.last_seen, p.created_at, u.created_at)
      < now() - make_interval(days => min_age_days)
```
`last_seen` NULL tidak lagi berarti "stale", melainkan **"tidak diketahui"
→ DIPERTAHANKAN**. Bila semua sumber waktu NULL → **jangan hapus**.

Verifikasi live: definisi memuat `coalesce(...)`; uji
`cleanup_stale_anonymous(7)` → 0 user hidup terhapus (aturan lama: ~105).

## Akar masalah 2 — `admin_list_deleted` mengabaikan `p_limit`
```sql
select jsonb_array_length(public.admin_list_deleted(5,0,true)->'items');
-- -> 1883 (HARUSNYA 5)
```
`LIMIT/OFFSET` diletakkan **di dalam** subquery `sub` yang kemudian
diagregasi oleh `jsonb_agg(...)` di query luar. LIMIT di subquery tidak
membatasi jumlah baris yang diagregasi di level luar.

Konsekuensi: aplikasi meminta 100 baris/halaman, server mengirim **seluruh
baris** — tiap refresh, tiap polling 30 detik.

Catatan: bug ini **tetap ada** meski `ORDER BY` sudah dipindah ke dalam
subquery pada `20260926050000` — yang diperbaiki waktu itu hanya **urutan**,
bukan **pemotongan**.

## Perbaikan 2 — potong sebelum agregasi (migrasi `20261002020000`)
ORDER BY + LIMIT + OFFSET dijalankan di subquery `page`, **baru** diagregasi
di luar. Ditambah `total_archive` / `total_pending` terpisah
(`20261002010000`): `total = arsip 1782 + pending 101`.

## Penelusuran lanjutan: DARI MANA 1646 "user hantu" itu?

### Kronologi — kenapa menumpuk lalu lepas sekaligus
`cron.job_run_details` untuk jobid 1:
| Tanggal 04:00 | Status |
|---|---|
| 24 Sep | **failed** `coin_ledger is append-only` |
| 25 Sep | **failed** idem |
| 26 Sep | **failed** idem |
| 27 Sep | **failed** idem |
| 28 Sep | **failed** idem |
| 29 Sep | succeeded (setelah `20260929000000`) |
| 30 Sep | succeeded |

Cleanup **GAGAL 5 hari** → akun stale **MENUMPUK**. Lalu:
```sql
select date_trunc('hour', deleted_at), count(*)
  from public.deleted_users where reason='stale_cleanup'
 group by 1 order by 2 desc;
-- 2026-09-28 23:00 -> 1594   <-- SATU JAM, SATU KALI
```
Cron jalan 04:00, jadi 28 Sep **23:00** = **run MANUAL** setelah fix
di-apply. 1594 = akumulasi 5 hari lepas sekaligus.

### Kenapa profilnya kosong? (signature 1646 baris)
```sql
select count(*) total, count(*) filter (where created_at is null),
       count(*) filter (where last_seen_at is null),
       count(*) filter (where brand='')
  from public.deleted_users
 where reason='stale_cleanup' and (nickname is null or nickname='');
-- total=1646, created_null=1646, lastseen_null=1646, tanpa_device=1646
```
**100% seragam** → penyebabnya satu, sistematis.

Akar teknis — `fn_archive_deleted_user` (`20260825160000`):
```sql
select nickname, ..., last_seen, created_at
  into v_nick, ..., v_last, v_created
  from profiles where id = p_uid;   -- TIDAK ADA BARIS → variabel tetap NULL
...
values (p_uid, coalesce(v_nick,''), ... v_last, v_created, ...)
--                 ^^^ jadi ''          ^^^^^^^^^^^^^^ tetap NULL
```
`v_nick` di-coalesce jadi `''`, tapi `v_last`/`v_created` **tidak** →
tersimpan NULL. Itulah tanda tangan 1646 baris hantu.

### Apa "user hantu" itu dan kenapa muncul
`auth.users` ada, tapi `profiles` **tidak pernah dibuat**:
- **Tidak ada trigger** di `auth.users` yang auto-membuat profil
  (diverifikasi: `pg_trigger` untuk `auth.users` = kosong).
- Profil hanya dibuat `AuthService.registerProfile()`, dipanggil dari layar
  register.
- `AuthProvider._init` (baris ~323): `signInAnonymously()` membuat
  `auth.users`, lalu `getProfile()` — bila `null`, kode **tidak membuat
  profil**, hanya lanjut (`if (_profile != null)`).
- Jadi setiap `signInAnonymously()` yang **tidak dilanjutkan** ke
  `registerProfile` (user menutup app, hanya lihat-lihat, crash) →
  meninggalkan **satu baris hantu**.

**Masih terjadi saat penulisan** — 6 hantu baru antara 30 Sep 01:08 dan
10:50 (semua `created_at` ≈ `last_sign_in_at` selisih ~20 ms, tanpa profil,
tanpa device).

### Kesimpulan
1. Tumpukan 1594/1671 = efek gabungan **dua** bug: cleanup gagal 5 hari
   (bug `coin_ledger`, sudah diperbaiki `20260929000000`) lalu lepas
   sekaligus, DAN logika fail-open (bug ini, diperbaiki `20261002000000`).
2. Korban terbesar (1646) bukan "user menganggur", melainkan **baris
   `auth.users` tanpa profil** — sampah teknis dari registrasi anon yang
   tidak selesai. Tidak berbahaya, tapi **salah kategori**:
   `cleanup_stale_anonymous` dirancang membersihkan akun menganggur, bukan
   baris hantu.
3. Risiko nyata yang dicegah: logika fail-open yang sama **juga** akan
   menghapus akun anon aktif yang datanya kosong.

## Verifikasi
- Ketiga definisi live sesuai: `cleanup_failsafe=true`,
  `masih_bug_lama=false`, `limit5=5`, `limit100=100`, halaman-1 vs 2 tidak
  overlap, `total = arsip + pending`.
- 89 test hijau; `check_migrations.sh` OK bersih.

## Pencegahan
- Test regresi:
  - `test/admin_service_test.dart` — limit/offset diteruskan apa adanya,
    `includePending` bisa dimatikan, rincian total tidak hilang.
  - `test/admin_provider_di_test.dart` — total dari server dipakai walau
    hanya 3 baris ter-load; fallback untuk DB lama.
- **Pelajaran umum (hapus data):** jangan pernah pakai
  `NOT EXISTS(<predikat positif>)`. Balik jadi `EXISTS(<kondisi aman>)` +
  syarat nilai jelas; perlakukan data NULL/absen sebagai **"JANGAN HAPUS"**.
- **Pelajaran paginasi:** `LIMIT`/`OFFSET` wajib di level yang benar-benar
  memotong. Bila hasil dibungkus agregat (`jsonb_agg`, `array_agg`), potong
  **sebelum** agregasi di subquery terpisah.
- **Pelajaran "perbaikan parsial":** `20260926050000` sudah menyentuh fungsi
  ini untuk urutan, tapi LIMIT-nya tidak ikut diperbaiki — selalu uji
  **jumlah baris yang keluar**, bukan hanya urutannya.
- **Pelajaran operasional:** cron yang GAGAL berhari-hari membuat data
  menumpuk dan lepas sekaligus saat pulih. Perlu alarm bila job penting
  gagal >1× berturut (saat ini tidak ada).

## Tindak lanjut yang SUDAH dikerjakan (2026-10-02)

Ketiga rekomendasi di bawah sudah diimplementasikan & diverifikasi live.

### A. Alarm cron gagal — `20261002030000_admin_cron_failure_alerts.sql`
Akar insiden ini adalah cron job 1 yang **GAGAL 5 hari tanpa ada yang tahu**.
Sekarang:
- Tabel `public.admin_alerts` (RLS admin-only) + `check_cron_failures()`.
- Job kritikal gagal **≥2× nyata** → dicatat, di-push ke device admin, dan
  tampil via `admin_cron_health()`.
- **`job startup timeout` DITOLAK dari hitungan** — awalnya alarm berisik
  karena timeout transient (job 27: 87 gagal dari 3465 run, semua pulih
  sendiri). Setelah difilter: hanya 1 alarm, yaitu bug nyata.
- Cron tiap jam menit 7 (jobid 30).
- Verifikasi: `select public.admin_cron_health(168)` → job 1 terdeteksi
  `fails=5/7` dengan error nyata; ada flag `currently_ok`.

### B. Pembersih baris hantu — `20261002040000_purge_ghost_users.sql`
- `purge_ghost_users(p_min_age_hours, p_dry_run)` — hapus HANYA `auth.users`
  anon yang **terbukti kosong total** (nol device, chat, pesan, koin, poin,
  lokasi, foto, blok, report, contact_message) dan cukup umur.
- **`p_dry_run` default `TRUE`** — hapus hanya bila dipanggil eksplisit
  `false`. Prinsip fail-safe: setiap kondisi adalah "hanya hapus bila
  terbukti kosong" (kebalikan bug fail-open yang menyebabkan insiden).
- `admin_ghost_stats()` untuk pantau: total hantu, yang siap dibersihkan,
  tren harian, dan total anon (pembanding).
- Cron harian 05:10 (jobid 33), setelah cleanup 04:00.
- **Hasil: 8 hantu dibersihkan, 107 akun anon aktif utuh.**

### C. Cegah hantu baru — `20261002050000_trigger_new_user_profile.sql`
- Trigger `AFTER INSERT ON auth.users` → membuat baris `profiles` minimal.
- **JEBAKAN YANG DITEMUKAN SAAT UJI (penting):** percobaan pertama memakai
  nickname default `'Anon'` dan **GAGAL diam-diam** —
  `profiles_nickname_unique` menolak baris kedua dst
  (`duplicate key value violates unique constraint "profiles_nickname_unique"`).
  Karena fungsi menelan error (`exception when others then null`), kegagalan
  itu TAK TERLIHAT dan hantu TETAP terbentuk — trigger seolah jalan padahal
  tidak. Terbukti: user uji setelah trigger terpasang masih punya profil NULL.
  → **nickname WAJIB digenerate unik** (`'Anon'` + 6 hex dari UUID + retry).
- Idempoten (`on conflict (id) do nothing`) — `registerProfile` tetap bisa
  menimpa bila user memilih nama sendiri.
- **Verifikasi: 2 user anon baru → `hantu = 0`.** `admin_ghost_stats()`
  → `total: 0`.

**Catatan pelajaran tambahan:** trigger SECURITY DEFINER yang menelan error
(`exception when others then null`) menyembunyikan kegagalan. Saat menulis
trigger semacam ini, UJI hasil akhirnya (baris benar-benar terbentuk),
jangan percaya bahwa "tidak ada error = berhasil".

## Rekomendasi yang masih bisa dipertimbangkan
- Pantau `admin_ghost_stats()` berkala; bila `daily_new` naik lagi berarti
  ada jalur lain yang membuat `auth.users` tanpa lewat trigger (mis. bulk
  import / pemanggilan admin).
