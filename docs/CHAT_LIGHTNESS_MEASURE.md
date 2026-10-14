# Cara Ukur — "Samakan Ringan Semua Halaman Chat" (chat admin/AI vs manusia)

Dokumen ini menjelaskan cara membuktikan bahwa optimasi pada perubahan ini
benar-benar membuat chat padat konten (khas balasan AI/admin) menjadi seringan
chat biasa. Perubahan terkait: gating link preview, memo/highlight blok kode,
filter URL, cache.

## Ringkasan perubahan

| Area | Sebelum | Sesudah |
|---|---|---|
| Link preview | auto-fetch di SETIAP bubble saat mount | auto-fetch HANYA 25 pesan terbaru; sisanya tap-to-load (`enabled:false`) |
| Fetch link preview | tak dibatasi (burst) | semaphore maks 3 paralel |
| URL preview | semua URL | filter: host generator gambar + ekstensi media dilewati |
| Cache link preview | RAM 50 | RAM 200 (LRU) |
| Blok kode | tokenize tiap build, selalu penuh | memo highlight + >25 pesan terbaru render ringkas (40 baris) |

Ambang gating seragam di 3 jalur: private chat (`private_chat_core.dart`),
admin monitor (`admin_chat_view_build.dart`), room chat (`room_chat_build.dart`).

## Instrumen yang dipakai

### 1. Selalu tersedia (tanpa flag)
- `LinkPreviewService.instance.networkFetchCount` — jumlah fetch jaringan
  (device/edge) sejak boot. **Turun = hemat jaringan.**
- `LinkPreviewService.instance.urlSkipCount` — jumlah URL yang dilewati filter
  (aset gambar). **Naik = lebih banyak fetch sia-sia yang dicegah.**
- `LinkPreviewService.instance.cacheLength` — isi cache RAM.
- `CodeBlock.renderCount` — jumlah render blok kode per sesi.

### 2. Frame metrics (butuh flag)
Jalankan/build dengan:
```
flutter run --dart-define=PERF_PROBE=true --profile
```
Log yang relevan:
- `build PrivateChat=<n>` — jumlah build layar chat (`private_chat_core.dart`).
- `build ChatList=<n>`, `build Composer=<n>` — pembanding.
- `[CACHE-TIME]` — sqlite & server fetch.
- `[CHAT-BUILD]`, `[PHOTO-DBG]`, `[TYPING]` — jalur pesan/media.
- `PerfProbe` frame timings (janky/raster) saat `measuring` aktif.

## Skenario uji (bandingkan chat admin vs chat manusia)

> Gunakan dua chat dengan **jumlah pesan serupa** agar adil. Bila berbeda,
> catat jumlahnya.

1. **Cold start → buka chat pertama.**
   - Catat: waktu tap→konten, `build PrivateChat`, janky frame, `networkFetchCount`,
     `urlSkipCount`.
2. **Warm → buka chat (dari cache).**
   - Ulang pencatatan. `networkFetchCount` delta harus ~0 untuk pesan di luar
     viewport.
3. **Scroll ke atas (pesan lama).**
   - Preview lama TIDAK boleh memicu fetch otomatis (tap-to-load).
4. **Ketuk satu placeholder "Ketuk untuk memuat pratinjau".**
   - Harus fetch tepat 1 URL, lalu tampil kartu.
5. **Buka chat dengan blok kode panjang (≥40 baris) di pesan lama.**
   - `CodeBlock.renderCount` naik, tapi tombol "Tampilkan N baris lagi" muncul;
     ketuk → diperluas inline.

## Target

| Metrik | Target |
|---|---|
| `networkFetchCount` per buka chat (pesan luar viewport) | ~0 |
| RPC/emit saat buka (admin vs manusia) | sama (tidak ada cabang khusus) |
| Frame build/raster admin | ≤ manusia + margin kecil |
| `build PrivateChat` untuk skenario sama | mendekati sama |

## Bukti kuantitatif data (opsional, read-only SQL)

Untuk chat admin vs manusia dengan id masing-masing:
```sql
select
  count(*)                                   as total,
  max(length(text))                          as max_len,
  count(*) filter (where text like '%```%')  as code_msgs,
  count(*) filter (where text ~* 'https?://') as url_msgs,
  count(*) filter (where type = 'image')     as image_msgs
from private_messages
where chat_id = '<chat_id>';
```

## Test otomatis

- `test/link_preview_disk_test.dart` — `isPreviewCandidate`, `extractUrl` filter.
- `test/link_preview_cache_test.dart` — cap cache 200.
- `test/code_block_memo_test.dart` — memo highlight + compact blok kode.
- Regresi: `test/chat_search_test.dart`, `test/flow_navigation_test.dart`,
  `test/post_card_test.dart`, `test/page_transition_test.dart`.
