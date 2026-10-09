# TikTok App Events (Business) SDK — ChatYuk

> Integrasi **TikTok Ads / App Events** di ChatYuk (tracking install, login,
> registrasi, purchase untuk optimasi iklan TikTok). SDK **native Android
> (Java/Kotlin)** — Flutter menjembatani lewat MethodChannel.
>
> Terakhir diverifikasi: **2026-10-09** — Events Manager: dataset **ChatYuk**
> (`com.chatyuk.chatyuk`) **Verified**, Attribution = TikTok SDK. Event
> terkirim (7 hari): Install 418, Registration 275, Launch App 2,082,
> Login 116. Live `token=true isInitialized=true` di HP (build dgn
> `--dart-define=TIKTOK_ACCESS_TOKEN`).

---

## 1. Kredensial (RAHASIA)

> ⚠️ **JANGAN** commit file ini ke repo publik / bagikan ke pihak tak
> berkepentingan. Siapa pun yang punya App Secret bisa mengirim event atas
> nama app Anda.

| Item | Nilai |
|---|---|
| **App ID** (package name) | `com.chatyuk.chatyuk` |
| **TikTok App ID** | `7691692882021187602` |
| **App Secret** | `TT2RbU3f6OkDcOPKBuE000wbBGtKL2Rb` |
| **Access Token** | `TT2RbU3f6OkDcOPKBuE000wbBGtKL2Rb` (dipakai saat build — lihat §4) |
| **Events Manager** | https://ads.tiktok.com/i18n/events_manager |
| **Developer Portal** | https://business-api.tiktok.com/portal |

> ⚠️ **Catatan penting:** App Secret di atas **sudah terekspos** di sesi kerja
> (2026-10-01). Untuk produksi:
> 1. Buka TikTok Events Manager → Settings → **App Access Token**.
> 2. Salin **Access Token** resmi (bukan App Secret).
> 3. **Regenerate** App Secret bila dianggap bocor.
>
> ✅ **Dikonfirmasi 2026-10-09 (Events Manager → Settings → Show App Secret):**
> nilai App Secret di atas **= yang ditampilkan Events Manager** (tidak berubah).
> Untuk **App Events SDK**, "App Access Token" = **App Secret** ini → token
> di build sudah BENAR. Yang penting: build rilis/profil WAJIB sertakan
> `--dart-define=TIKTOK_ACCESS_TOKEN=TT2RbU3f6OkDcOPKBuE000wbBGtKL2Rb`
> (kalau tidak → `token=false`, pelacakan terbatas).

---

## 2. Ringkasan Integrasi

| Komponen | File | Keterangan |
|---|---|---|
| Repo JitPack | `android/build.gradle.kts` | `maven { url = uri("https://jitpack.io") }` |
| Dependency | `android/app/build.gradle.kts` | `com.github.tiktok:tiktok-business-android-sdk:1.7.1` |
| App ID / TT App ID | `android/app/src/main/res/values/strings.xml` | `tiktok_app_id`, `tiktok_tt_app_id` |
| Native bridge | `android/app/src/main/kotlin/com/chatyuk/chatyuk/TikTokBridge.kt` | init/identify/track/purchase/logout |
| Channel registration | `MainActivity.kt` | channel `com.chatyuk.chatyuk/tiktok` |
| Dart service | `lib/services/tiktok_service.dart` | `TikTokService` + enum `TikTokEvent` |
| Access Token define | `lib/config/env.dart` | `TIKTOK_ACCESS_TOKEN` (dart-define) |
| Init bootstrap | `lib/main.dart` | `TikTokService.instance.init(...)` |
| Wiring auth | `lib/providers/auth_provider.dart` | identify + LOGIN/REGISTRATION + logout |

---

## 3. Cara Kerja (Alur)

```
Dart (TikTokService)
   │  MethodChannel "com.chatyuk.chatyuk/tiktok"
   ▼
Kotlin (TikTokBridge) ──► TikTokBusinessSdk (native)
   │
   │  AndroidManifest / strings.xml → App ID, TikTok App ID
   │  --dart-define TIKTOK_ACCESS_TOKEN → Access Token
   ▼
TikTok Events Manager  (event terkirim untuk optimasi iklan)
```

### Event yang dikirim
| Event | Kapan | Lokasi |
|---|---|---|
| `REGISTRATION` | User selesai isi profil / daftar | `AuthProvider.registerProfile` |
| `LOGIN` | Login email & Google (user lama) | `AuthProvider.signInWithEmail` / `signInWithGoogle` |
| `identify(...)` | Tiap login/daftar (external id = uid) | `AuthProvider._syncTikTok` |
| `logout()` | Saat sign out (reset identitas) | `AuthProvider.signOut` |

### Belum dipakai (siap pakai, tinggal panggil)
`GENERATE_LEAD`, `RATE`, `START_TRIAL`, `SUBSCRIBE`, `ADD_PAYMENT_INFO`,
`COMPLETE_TUTORIAL`, `SEARCH`, `SPEND_CREDITS`, `IN_APP_AD_CLICK`,
`IN_APP_AD_IMPR`, dan **`purchase(...)`** (event pendapatan).

Contoh memicu purchase (mis. saat top-up YukCoin sukses):
```dart
await TikTokService.instance.purchase(
  value: 50000,       // total transaksi
  currency: 'IDR',
  contentId: 'yukcoin_50k',
  contentType: 'yukcoin',
);
```

---

## 4. Cara Build (dengan Access Token)

Token **tidak** ditulis di source — disuntik saat build via `--dart-define`:

```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --dart-define=TIKTOK_ACCESS_TOKEN=TT2RbU3f6OkDcOPKBuE000wbBGtKL2Rb
```

Play / AAB:
```bash
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor playProd --dart-define=APP_FLAVOR=play \
  --dart-define=TIKTOK_ACCESS_TOKEN=TT2RbU3f6OkDcOPKBuE000wbBGtKL2Rb \
  --obfuscate --split-debug-info=build/app/symbols
```

> Bila `TIKTOK_ACCESS_TOKEN` tidak di-define → SDK tetap init (App ID dari
> strings.xml) tapi tanpa token; pelacakan mungkin terbatas. **Tidak
> menggagalkan build/app.**

### Verifikasi init (logcat)
```bash
adb logcat | grep ChatYukTikTok
# Harus muncul:
# I ChatYukTikTok: initialize success: appId=com.chatyuk.chatyuk
#   ttAppId=7691692882021187602 token=true isInitialized=true
```

---

## 5. Pelajaran Teknis (PENTING — jangan diulang)

Debug 2026-10-01 menemukan 4 jebakan saat integrasi:

1. **Init SDK ASYNC.** `TikTokBusinessSdk.isInitialized()` **belum** `true`
   tepat setelah `initializeSdk()` — `sdkInitialized` di-set di dalam
   `TTAppEventLogger.initConfig(...)`. **Wajib** pakai
   `TTInitCallback.success()` untuk tahu kapan selesai.

2. **`updateAccessToken` menolak bila SDK belum init.** Bytecode SDK:
   `if (!isInitialized()) return;`. Jadi token **harus** di-set di dalam
   `success()` (setelah init), **bukan** sebelum `initializeSdk`.

3. **R8 men-shrink string resource** yang diakses via `getIdentifier(...)`
   (reflection). Di release (`isMinifyEnabled=true`), `tiktok_app_id`/`tt_app_id`
   hilang → `getString` kosong. **Fix:** akses via `R.string.tiktok_app_id`
   langsung (referensi statis tidak di-shrink).

4. **App ID/TT App ID via `TTConfig`**, bukan meta-data manifest. SDK v1.7
   **tidak** membaca meta-data `com.tiktok.sdk.*`; set lewat
   `.setAppId()` + `.setTTAppId()`.

---

## 6. Ketergantungan SDK

```
implementation("com.github.tiktok:tiktok-business-android-sdk:1.7.1")
implementation("androidx.lifecycle:lifecycle-process:2.8.7")       // deteksi foreground
implementation("androidx.lifecycle:lifecycle-common-java8:2.8.7")
implementation("com.android.installreferrer:installreferrer:2.2")  // atribusi install
```
Proguard/R8: SDK sudah menyertakan `consumer-rules` (`-keep class com.tiktok.**`).

---

## 7. Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| `isInitialized=false` di log | baca `isInitialized()` sebelum init async selesai | pakai `TTInitCallback.success()` |
| `App ID / TikTok App ID kosong` | string di-shrink R8 / salah key | akses `R.string.tiktok_app_id` langsung |
| `token=false` walau sudah di-define | token di-set sebelum init | set di `success()` |
| Event tak muncul di Events Manager | access token salah/kosong, atau Test Mode | pastikan token resmi; cek Events Manager → Test Events |
| Build gagal `recorded_uses.json not found` | cache build korup | `flutter clean && flutter pub get` |

---

## 8. Referensi

- SDK repo: https://github.com/tiktok/tiktok-business-android-sdk
- Dokumentasi developer: https://business-api.tiktok.com/portal/docs?id=1739584951798785
- Panduan integrasi: https://ads.tiktok.com/help/article/how-to-integrate-tiktok-app-events-sdk
