# Meta App "ChatYuk" — yang dipakai untuk FB Ads (App Install)

> Satu-satunya Meta App yang dipakai ChatYuk. Jangan buat baru / jangan pakai
> yang lain (riwayat duplikat di bawah).

## Kanonis (DIPAKAI)

- **Nama:** ChatYuk
- **App ID:** `4699753480345190`
- **Client Token:** `782f99654ddbf22be6b59900e08da2ab`
  (Settings → Advanced → Token Klien)
- **Mode:** Pengembangan (Development) — cukup untuk Test Events
- **Email kontak:** zunixe@gmail.com
- **Portofolio bisnis pemilik:** `ChatYuk` (business_id `1040399342313258`,
  Unverified) — aplikasi sudah dimiliki portofolio ini sejak pembuatan
  (terverifikasi di Business Settings → Aplikasi → detail "Dimiliki oleh:
  ChatYuk", 2026-09-19). Sengaja TIDAK dipindah ke CV Zunixe Berkah Jaya
  (keputusan user).
- **Dashboard:** https://developers.facebook.com/apps/4699753480345190/dashboard/
- **Platform Android** (Settings → Basic):
  - Store: Google Play Store
  - Nama Paket: `com.chatyuk.chatyuk`
  - Nama kelas: `com.chatyuk.chatyuk.MainActivity`
  - Hash Kunci: `jMxC4/6TNyFs5CUOK/zLIpQeUKI=` (dari keystore v2)
- **Isi di kode:**
  - `lib/config/meta_config.dart` (`appId` + `clientToken`)
  - `android/app/src/main/res/values/strings.xml`
    (`facebook_app_id` + `facebook_client_token`)
  - Inisialisasi: `MetaAnalytics.init()` di `lib/main.dart` → `bootstrap()`

## Duplikat (DIARSIPKAN — jangan dipakai)

Terbuat otomatis akibat error "Tindakan Ini Tidak Diizinkan" saat pembuatan
(rate-limit Meta; app tetap kecreate walau dialog error). Keduanya sudah
diarsipkan via halaman Aplikasi Saya:

- `2305320633368590` (ChatYuk — arsip)
- `1064193909798663` (ChatYuk — arsip)

## Belum dilakukan (follow-up manual)

1. ~~Hubungkan portofolio bisnis~~ — SELESAI tanpa tindakan: aplikasi sudah
   dimiliki portofolio `ChatYuk` sejak pembuatan (bukan CV Zunixe Berkah
   Jaya; tidak ada request approval yang menggantung — halaman Permintaan
   kosong). Keputusan: tetap di sini.
2. **Go Live** (switch Mode Pengembangan → Live) setelah Test Events hijau.
   Syarat: URL kebijakan privasi + ikon app + kategori terisi di Settings.
3. **Update Play Data Safety**: device ID dibagikan ke Meta (tujuan: iklan).
4. Kampanye App Installs di Ads Manager menarget Meta App ini.

## Riwayat setup (2026-09-19, via Playwright + Chrome asli)

- Login FB manual user (2FA) → developers.facebook.com → Buat Aplikasi
  (nama ChatYuk, use case "iklan aplikasi", bisnis CV Zunixe Berkah Jaya).
- Pembuatan kena rate-limit 3x tapi app tetap terbentuk (3 duplikat).
- Dipilih `4699753480345190` sebagai kanonis; 2 sisanya diarsipkan.
- Client Token diambil dari Settings → Advanced.
- Platform Android + key hash diisi dan terverifikasi persist (reload).
