# REFERENSI EKSTERNAL — Telegram (benchmark arsitektur)

> Catatan alamat sumber + apa yang sudah diadopsi ke ChatYuk. Dipakai supaya
> audit/optimasi berikutnya punya acuan konkret (bukan tebakan).

## Sumber kode Telegram Android

| Sumber | Alamat |
|---|---|
| **Resmi (DrKLO)** | https://github.com/DrKLO/Telegram |
| Fork yang kamu lihat | https://github.com/TelegramOrg/Telegram-Android |
| Clone (dengan submodule) | `git clone --recursive --shallow-submodules https://github.com/DrKLO/Telegram.git Telegram` |
| Klon probe lokal (read-only) | `/var/folders/8x/7hc6m_dj31b6q125bx2lyzpr0000gn/T/opencode/tg_probe` |

Dokumentasi API/protokol:
- API: https://core.telegram.org/api
- MTProto: https://core.telegram.org/mtproto

## Teknologi Telegram (ringkas)
Java (mayoritas) + Kotlin + **NDK (C/C++)** · UI **native View** (bukan
Flutter/Compose) · rendering **GL custom** · jaringan **MTProto** (socket
sendiri, BUKAN FCM/WebSocket) · DB SQLite custom · image loader **custom**
(`ImageLoader.java`, bitmap pool) · build Gradle + NDK 27.2 / SDK 36.
Lisensi GPL-2.0.

## Yang SUDAH diadopsi ChatYuk (pola, bukan salin kode)
| Pola Telegram | Adopsi ChatYuk | Bukti |
|---|---|---|
| Cap cache **dinamis** (`memoryClass/7`) | cap imageCache adaptif RAM (`image_cache_budget.dart`) | §48 |
| `smallImagesMemCache` (cache kecil terpisah) | `AvatarImageCache` terpisah | §48 |
| Pool byte + `BitmapFactory.Options` reuse | `ImageBridge.kt` (RGB_565 + optionsPool) | §48 |
| `WebPage` preview server-side | Edge Function `link-preview` + device-first | §50 |
| Preview foto cache disk | `LinkPreviewImage` (MediaDiskCache) | §50 |

## Yang TIDAK bisa disalin (arsitektur beda)
- MTProto socket permanen → ChatYuk pakai Supabase realtime + FCM (gate baterai §46).
- GL/Choreographer double-buffer video → tersembunyi di ExoPlayer/Impeller.
- Native VoIP sendiri → ChatYuk `flutter_webrtc`.

---

## WhatsApp — CLOSED-SOURCE (tidak ada source app)

**Tidak ada** source code aplikasi WhatsApp (Android/iOS) di GitHub. App-nya
**proprietary**. Org resmi `github.com/WhatsApp` hanya berisi **library/alat
pendukung**, BUKAN app-nya.

| Repo resmi WhatsApp | Isi | Bahasa / Lisensi |
|---|---|---|
| `WhatsApp/stickers` | API + sample app untuk **sticker pack** pihak ketiga | Java · NOASSERTION |
| `WhatsApp/StringPacks` | Ekstrak string Android → format efisien | Java · Apache-2.0 |
| `WhatsApp/erlfmt` | Formatter kode Erlang | Erlang |
| `WhatsApp/power_shell` | Erlang shell lanjutan | Erlang |
| `WhatsApp/stud` | Scalable TLS Unwrapping Daemon | C |
| `WhatsApp/erl_img` | Pemrosesan gambar (Erlang) | Erlang |
| `WhatsApp/snappy-erlang-nif` | NIF Erlang utk kompresor Snappy | C++ |
| `WhatsApp/WADebug` | CLI troubleshooting WhatsApp Business API | Python · MIT |
| `WhatsApp/WhatsApp-Business-API-Setup-Scripts` | Skrip setup Business Cloud API | — |

**Konsekuensi untuk ChatYuk:**
- **WhatsApp** = referensi **perilaku/UX** saja (chat list, centang, gaya M3) —
  implementasinya **tak bisa dibaca**.
- **Telegram** (`DrKLO/Telegram`) = referensi **kode** nyata (sudah dipakai:
  cap cache adaptif §48, pool bitmap §48, link preview §50).
- Berguna bila nanti mau fitur **sticker**: `WhatsApp/stickers` = API/sample
  resmi yang bisa ditiru (format pack + payload intent Android).

