# E2E ChatYuk (Maestro)

Test **end-to-end UI** di HP/emulator nyata — lapisan yang tidak tercakup
62 file unit/widget test.

## ⛔ LARANGAN — jangan pakai akun user asli untuk test

**JANGAN pernah mengirim/menyisipkan pesan dengan `sender_id` milik user
asli** (lewat SQL, Management API, `net.http_post`, Maestro, atau skrip).
Pesan yang muncul seolah dari user asli = **disangka scam / akun dibajak**.

Aturan:
1. Test kirim pesan HANYA dari akun **dummy** (`dummy_accounts`) atau akun
   test khusus milik dev.
2. Untuk chat 1:1 dengan user asli → **read-only** (jangan insert atas
   namanya).
3. Tandai data test (`[TEST]`) dan bersihkan tuntas setelahnya:
   `private_messages`, `ai_reply_log`, `ai_reply_claims`, lalu kembalikan
   `private_chats.last_message`/`last_message_at` ke pesan asli.
4. Ingat: hapus baris server **TIDAK** menghapus cache lokal HP
   (`chatyuk_messages_v1.db`) — pesan masih terlihat di history user.

## Kenapa Maestro, bukan `integration_test`

Repo ini pernah **gagal build rilis** karena dev-dep `integration_test`:
plugin-nya bocor ke `GeneratedPluginRegistrant.java` build release padahal
Gradle release tidak menyertakannya →
`package dev.flutter.plugins.integration_test does not exist`.
Lihat `integration_test/README.md` + `test/regression/r_build_deps_test.dart`
(yang mengunci larangan itu).

Maestro **black-box** lewat adb: **nol perubahan pada `pubspec.yaml`** →
tidak bisa merusak build.

## Pasang

```bash
brew install mobile-dev-inc/tap/maestro   # CLI (formula, bukan cask GUI)
maestro --version                          # harus keluar versi
```

## Jalankan

```bash
scripts/e2e/run.sh            # semua flow
scripts/e2e/run.sh 01         # flow yang namanya mengandung "01"
DEV=192.168.18.33:46197 scripts/e2e/run.sh
```

Skrip otomatis: `force-stop` app **admin** (agar Maestro tidak salah baca UI
admin — pernah terjadi), cek APK user terpasang, lalu jalankan flow.

Alur lengkap: build + install APK → `scripts/e2e/run.sh`.

## Daftar flow

| Flow | Yang dikunci |
|---|---|
| `01_entry_new_profile.yaml` | Jalur masuk utama: entry → isi nickname → submit → main nav. **Tanpa `clearState`** bila ingin mempertahankan sesi |
| `02_entry_google_button.yaml` | Tombol "Lanjutkan dengan Google" → account picker native terbuka (tidak memilih akun) |
| `03_entry_email_forms.yaml` | "Daftar dengan Email" → form Register; "Sudah punya akun? Login" → form Login |
| `04_chat_send_message.yaml` | Tab Online → buka chat → ketik → tombol `send` → bubble tampil |
| `05_call_audio_video.yaml` | Menu call → **audio** & **video** → layar call → "Akhiri" → kembali ke chat |

## Hal yang WAJIB dipahami sebelum mengubah flow

1. **Field nickname auto-submit.** `profile_form_card.dart` memakai
   `textInputAction: done` + `onSubmitted`. Jadi `inputText` yang diakhiri
   Enter **langsung masuk app** — assertion kontrol profil harus dilakukan
   **sebelum** mengetik nickname.
2. **Tombol kirim punya key stabil:** `ValueKey('send')` di
   `chat_composer_input.dart` → `tapOn: {id: "send"}` (jangan tebak ikon).
3. **App admin menutupi.** Bila `com.chatyuk.chatyuk.admin` terbuka, Maestro
   membaca UI-nya → selector "tidak ketemu" palsu. `run.sh` sudah
   `force-stop`; kalau menjalankan `maestro` manual, lakukan sendiri.
4. **`appId` = `com.chatyuk.chatyuk`** (flavor apkpure). Flavor `play`
   memakai appId sama; flavor `admin` beda (`.admin`) — jangan diuji di sini.
5. **Flow data-dependent di-skip, bukan gagal.** `04`/`05` butuh minimal satu
   user online; kalau tidak ada, flow berhenti dengan `stopFlow` +
   `takeScreenshot: e2e-skip-*` (kondisi data, bukan regresi kode).

## Batasan (jujur)

- **Tidak** menguji: tersambungnya media WebRTC (butuh 2 device + lawan),
  push FCM, login Google sungguhan (butuh kredensial), OTP email.
- **Tidak jalan di CI** `ubuntu-latest` (tanpa emulator/KVM). Jalankan lokal
  atau di runner macOS/self-hosted.
- Maestro butuh app **sudah terpasang**; ia tidak mem-build.
- Artefak kegagalan (screenshot/hierarki) di
  `~/Library/Application Support/*/maestro/tests/<timestamp>/`.
