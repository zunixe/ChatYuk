# INVENTARIS PERFORMA HALAMAN ChatYuk

> Status audit §8 (dokumen "Global Zero-Lag Navigation"). Diperbarui 2026-10-12.
>
> **Cara baca kolom "Terukur":** ✅ = diukur di HP fisik (Xiaomi 24129PN74G,
> build profile + `PERF_PROBE`); 🔶 = terverifikasi dari kode/profil sebagian;
> ⏳ = belum diukur (kandidat uji lanjutan).

## Standar (§9) — target terukur

| Metrik | Target | Kondisi |
|---|---|---|
| Respons input → feedback | p95 ≤ 100 ms | build p50 2.5 ms, raster p50 1.8 ms |
| Transisi → konten awal | p95 ≤ 200 ms | tanpa operasi eksternal |
| Frame build | ≤ 16.7 ms (60 Hz) | terukur p90 3.2 ms |
| Frame raster | ≤ 16.7 ms | terukur p90 3.0 ms |
| Jank | 0 | **0/4000 frame** (skenario normal) |

## Shell navigasi (semua halaman)

| Komponen | Implementasi | Status |
|---|---|---|
| Bottom nav | `AppBottomNav` — `select` angka | ✅ |
| Tab host | `IndexedStack` lazy (`_visitedTabs`) + `_TabFreeze` | ✅ |
| State tab | `navProvider` (global, non-autoDispose) | ✅ + test `flow_navigation_test` |
| Tema | `themeProvider.select(isDark)` | ✅ |
| Trim memori | foreground-idle 15 s + resume `[0,2,4,7,10]s` | ✅ (memori stabil) |

## Halaman utama (tab)

| Halaman | Bootstrap | Data | Status | Catatan |
|---|---|---|---|---|
| **Online** (`online_users_screen`) | post-frame | cache disk + RPC | ✅ terukur | `online.diskLoad` 178–305 ms, avatar anti-kedip |
| **Chats** (`chats_screen`) | cache-dulu | `chat.listFetch` (poll 30 s gated) | ✅ terukur | listFetch 307 ms avg = **latency jaringan** (DB 0.5 ms) |
| **Timeline** (`timeline_screen`) | prewarm 3 s | `timeline.rpc` | ✅ terukur | scroll 58 kartu → 0 janky (§47b) |
| **Profile** (`profile_screen`) | — | points/wallet | ✅ terukur | RPC coalesced |

## Halaman detail & modal

| Halaman | Status | Catatan |
|---|---|---|
| **PrivateChat** | ✅ terukur | ZERO-JANK: tap push instan, initState post-frame, media lazy (§48) |
| **AdminChatView** | ✅ terukur | daftar instan (preload), video poster (§47/§48) |
| **UserInfo / SocialList** | ✅ terukur | cache-dulu (`peekProfileCache` sinkron frame-1) |
| **Admin panel tabs** | 🔶 | initState `Future.microtask` (bukan sinkron) — belum diukur per-tab |
| Story viewer / room chat / group | 🔶 | pola async sama; belum profil per-halaman |
| Nearby / search / settings | ⏳ | belum diukur langsung |

## Jalur kritis yang sudah diuji (§9–§10)

| Skenario | Hasil |
|---|---|
| Cold start | RPC boot p50 369 ms (dulu 890) — §48b |
| Warm navigation (pindah tab) | 200× tab → memori stabil 238 MB — §48c |
| Cache hit / miss | foto mem-hit 0 ms; sqlite 3–37 ms |
| **Offline (wifi+data mati)** | **app tidak crash/ANR**, error jaringan tertangkap, UI responsif |
| **Recovery online** | `[WARMUP] koneksi RPC siap` → pulih otomatis |
| Sesi panjang (30× chat + 200× tab) | no leak, PSS 300→238 MB — §48c |
| Buka chat pertama | 2/1593 frame (0.13%, by-design) — §48d |
| Buka chat video (regresi disposed image) | diperbaiki — §48e |

## Belum diukur (kandidat lanjutan)

- Network **throttle** (bukan offline) — butuh root/tc; belum bisa di device.
- Perangkat **low-end** (HP kedua) — belum tersedia.
- Per-tab **admin panel** frame time.
- Nearby / story viewer / room chat frame time.

## Regression otomatis (§10)

| Test | Cakupan |
|---|---|
| `test/flow_navigation_test.dart` | 100× pindah tab, 30× buka-tutup chat, double-tap guard |
| `test/flow_chat_test.dart` / `flow_points_test.dart` / `flow_story_test.dart` | alur fitur (hermetic) |
| `test/nav_guard_test.dart` | anti route ganda |
| `scripts/stress/device.sh` | stress perangkat sungguhan (Lapis 4) |
