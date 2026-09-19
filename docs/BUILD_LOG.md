# BUILD_LOG — catatan build + install ke HP

Aturan: tiap selesai build + stream install, tambah baris di tabel bawah.
Format: tanggal | branch | flavor | isi | hasil install.

| Tanggal | Branch | Flavor | Isi | Install |
|---|---|---|---|---|
| 2026-09-17 19:34 | develop | adminProd | Tint primary bubble terpilih private chat; kartu online balik bgCard + ikon transparan; preview + ✓✓ list Pesan; tombol teman ikon | Success (stream install 192.168.18.33) |
| 2026-09-17 20:05 | develop | adminProd | Menu ⋮ private chat: ikon kanan tiap baris (Ikuti/Tambah Teman/Blokir/Laporkan) + card rounded 14 | Success (stream install 192.168.18.33) |
| 2026-09-17 20:20 | develop | adminProd | Menu ⋮ private chat: divider antar baris + ikon Ikuti/Tambah Teman putih | Success (stream install 192.168.18.33) |
| 2026-09-17 20:35 | develop | adminProd | Menu ⋮ private chat ikon pindah kiri + divider menu list Chat; ikon tambah-teman Pesan + ikuti/chat online putih | Success (stream install 192.168.18.33) |
| 2026-09-17 20:50 | develop | adminProd | Ikon Ikuti/Tambah Teman menu ⋮ ikut warna tema (putih banget kaya Grup Baru) | Success (stream install 192.168.18.33) |
| 2026-09-17 21:05 | develop | adminProd | Ikon Tambah Teman menu ⋮ ganti person_add_alt (beda dari Grup Baru), warna+ukuran tetap | Success (stream install 192.168.18.33) |
| 2026-09-17 21:20 | develop | adminProd | FULL flutter clean rebuild (ikon Tambah Teman tak berubah di HP) | Success (stream install 192.168.18.33) |
| 2026-09-17 21:30 | develop | adminProd | Ikon tambah-teman Pesan 16→20 samakan Online | Success (stream install 192.168.18.33) |
| 2026-09-17 22:10 | develop | adminProd | Notif ala WA: MessagingStyle+grup+ringkasan, aksi Balas inline & Tandai dibaca (fg+bg), category message, visibility public, autoCancel | Success (stream install 192.168.18.33) |
| 2026-09-18 07:05 | develop | adminProd | Perf: TickerMode per tab, select ganti watch, recompute keluar build, RepaintBoundary, prewarm tab, throttle notifyActivity | Success (stream install 192.168.18.33) |
| 2026-09-18 07:35 | develop | adminProd | Respons sentuhan: long-press 500→320ms (AppGestureDetector), tooltip 320ms, haptic tombol kirim, fix spinner logout (timeout) | Success (stream install 192.168.18.33) |
| 2026-09-18 07:50 | develop | adminProd | PerfProbe: instrumentasi waktu fetch (chat.listFetch, online.diskLoad) | Success (stream install 192.168.18.33) |
| 2026-09-18 18:35 | develop | adminProd | Story perf: notifier thumbnail galeri, RepaintBoundary, bulk markSeen, viewer lifecycle, composer 1-hop; index story_views + RPC mark_story_seen_bulk | Success (stream install 192.168.18.33:33121) |
| 2026-09-19 05:26 | develop | adminProd | Header private chat: umur/gender fallback profil live (fix hilang-timbul) + verified pakai efektif; dot status samakan list (4CAF50/FFC107/9E9E9E, border putih 1.5); ai-reply diagram prompt fix (TERPISAH, deploy aktif) | Success (push 192.168.18.33:33121) |
| 2026-09-19 06:41 | develop | playProd | Meta App Events: facebook_app_events 0.30.5 + manifest meta-data + MetaAnalytics.init (App ID 4699753480345190); FULL clean (plugin native baru); keystore v2 verified | Success (push chatyuk_play.apk 192.168.18.33:33121) + stream install 192.168.18.240:38199 |
| 2026-09-19 11:20 | develop | adminProd | Fase 2 modular chat: ChatOutboxMixin/ChatSelectionMixin/VoiceRecorderMixin/chat_photo_helper/ChatComposerInput (buang duplikasi private↔room) | Success (stream install 192.168.18.240:38199 + push 192.168.18.33:33121) |
| 2026-09-19 12:05 | develop | adminProd + apkpureProd | Room/grup: buang centang status (banner + bubble) + tombol emoji composer disamakan dengan private | Success (stream install keduanya di 192.168.18.240:38199 & 192.168.18.33:33121) |
| 2026-09-19 12:40 | develop | adminProd + apkpureProd | Fase 3a/3b modular: coin_gift_dialogs bersama (koin/gift/lapor) + room_widgets (UserChip/HeaderToggle/SheetIcon) | Success (stream install keduanya di 192.168.18.240:38199 & 192.168.18.33:42003) |
| 2026-09-19 13:20 | develop | adminProd + apkpureProd | Fase 4: ChatService 2278→408 baris (ChatBase + mixin per domain via `part`); pola extension DITOLAK (putus interface/mock) | Success (stream install keduanya di 192.168.18.240:38199 & 192.168.18.33:42003) |

## Catatan penting: build probe & the underlying provider Sign-In

Build `--profile`/`--debug` **selalu** bikin the underlying provider Sign-In gagal (`DEVELOPER_ERROR`)
karena ditandatangani debug key (SHA-1 `ff:1f:f6:2d:...`) yang tidak terdaftar
di the underlying provider Cloud. App rilis ditandatangani keystore rilis
(SHA-1 `8C:CC:42:E3:...`) dan aman.

Probe (`PERF_PROBE=true`) hanya bicara di profil/debug → **jangan pasang ke HP
kerja**. Untuk ukur render pakai app rilis + `SurfaceFlinger --latency`
(lihat `docs/PERFORMANCE.md` bagian 1 & 3). Probe app `adminDev` pernah dicoba
lalu **dihapus** (tetap butuh SHA-1 terdaftar sendiri).
