# STRESS TEST — hasil + rekomendasi

> Eksekusi: 2026-09-18/19 (~3 jam), branch `develop`, plan **Free**, region
> **ap-northeast-1** (Tokyo). Skrip permanen di `scripts/stress/` supaya bisa
> dijalankan ulang: `monitor.sh`, `accounts.sh`, `bench_rpc.sh`,
> `bench_contention.sh`, `k6_api.js`, `realtime.sh` + `realtime.mjs`,
> `device.sh`.

## 0. Ringkasan eksekutif

| Pertanyaan | Jawaban |
|---|---|
| Kuat sampai berapa user? | **HTTP/RPC aman s/d 200 VU** (p95 <170ms, error <0.3%). **Realtime mulai degradasi di ~500 koneksi**, OK penuh s/d 300. |
| Target 500 user tercapai? | **Belum.** Bottleneck = realtime (~500) + limit plan Free (realtime 200, koneksi 60). DB & HTTP masih longgar. |
| Perlu upgrade plan? | **Ya, kalau target 500 online bareng.** Lihat rekomendasi P1. |
| Ada bug/inkonsistensi? | **Tidak.** Kontensi 100 tulis paralel: 0 error, counter konsisten. |

## 1. Baseline (sebelum test)

| Metrik | Nilai |
|---|---|
| auth.users | 1.139 |
| profiles | 95 |
| private_messages | 1.450 |
| private_chats | 125 |
| stories / rooms | 2 / 252 |
| Koneksi DB | 35 / 60 |
| Cron aktif | 16 (5 jalan tiap menit) |

RPC termahal (`pg_stat_statements`): `ai_presence_tick` 284ms, `dummy_heartbeat`
80ms, `story_tray` 29ms. Latensi jaringan dasar Mac→Tokyo **~430ms** vs CPU
query **~29ms** → 85% waktu RPC habis di perjalanan, bukan di query.

## 2. Hasil per lapis

### Lapis 1 — DB/RPC langsung (via HTTP, RLS aktif, n=20)

| RPC | mean | p50 | p95 | max |
|---|---|---|---|---|
| story_tray | 228ms | 205ms | 248ms | 690ms |
| get_online_users | 212ms | 210ms | 255ms | 272ms |
| list_posts | 202ms | 184ms | 288ms | 344ms |
| timeline_pricing | 191ms | 184ms | 232ms | 245ms |

### Lapis 1 — Kontensi (20 paralel × 5 = 100 insert ke 1 chat)

- Throughput **56.9/s**, p50 232ms, p95 590ms, max 608ms, **error 0**.
- Konsistensi: `message_count=100` == pesan nyata 100. Trigger
  `handle_new_private_message` **tidak** kehilangan hitungan walau 20 thread
  menabrak baris chat yang sama. **Tidak ada lock wait.**

### Lapis 2 — k6 HTTP (skip `ai-reply` karena biaya token)

| Skenario | p95 | error | throughput | Verdict |
|---|---|---|---|---|
| Load 50→200 VU | 152ms | 0.20% | 49 req/s (7.902 req) | **LULUS** |
| Spike 0→200/10s | 165ms | 0.31% | 72 req/s (5.086 req) | **LULUS** |
| Soak 50 VU 15 mnt | 170ms | 0.05% | 29 req/s (28.608 req) | **LULUS, stabil** |

Koneksi DB selama test: maks **37/60**, lock waiting **0** (391 sampel monitor).

### Lapis 3 — Realtime websocket (titik terlemah)

| Koneksi | Hasil | Settle |
|---|---|---|
| 50 / 100 / 200 / 300 | 100% OK | ~1 detik |
| 500 | 499/500 (1 timeout) | 30 detik |
| 1000 | 996/1000 (4 timeout) | 31 detik |

**Batas praktis ≈ 300–400 koneksi.** Catatan: limit resmi plan Free = 200
concurrent realtime — hasil test (300 OK) kemungkinan karena toleransi burst;
**jangan jadikan patokan**, tetap anggap 200 sebagai batas resmi.

### Lapis 4 — Device (Xiaomi 24129PN74G, app rilis admin)

| Metrik | Nilai |
|---|---|
| Cold start (3×) | **600 / 653 / 766 ms** |
| Memori idle | PSS 195 MB |
| Memori app dibuka | PSS 268 MB |
| Memori setelah scroll | PSS ~242 MB (stabil, tidak bocor) |
| Frame latency | **Tidak terukur** — `SurfaceFlinger --latency` kosong untuk layer Flutter di MIUI ini (sudah dicoba 5×: layer Activity, BLAST, SurfaceView). Lihat `PERFORMANCE.md` §1 untuk metode yang jalan. |

## 3. Yang harus diperbarui setelah ini (prioritas)

### P1 — Blocker target 500
- [ ] **Upgrade Supabase ke Pro** ($25/bln): realtime 200→500+, koneksi 60→
      200+, CPU dedicated. Tanpa ini target 500 tidak mungkin (batas platform,
      bukan kode).
- [ ] Setelah upgrade: ulangi Lapis 3 sampai 600 koneksi untuk validasi.

### P2 — Optimasi berdampak (tanpa upgrade)
- [ ] **Kurangi channel realtime per user.** Sekarang ~24 titik `channel()`
      (per-chat `private_<chatId>`, `stories-realtime`, `story-views-realtime`,
      `social-rt`, …). Tiap channel = 1 koneksi logis. Gabungkan yang
      memungkinkan (mis. satu channel `user` untuk event sosial).
- [ ] **Jarang-kan polling `Timer.periodic`** (10× 30 detik, 7× 1 detik).
      Audit satu-satu: mana yang bisa diganti event realtime / diperjarang.
- [ ] **Region**: server di Tokyo, user di Indonesia. Kalau mayoritas user
      Indonesia, pertimbangkan region Singapore (latensi ~430ms → ~50ms akan
      memangkas mayoritas waktu RPC — 85% waktu sekarang adalah jaringan).
- [ ] **Cron tiap menit** (`chatyuk-presence-idle`, `cleanup-room-signals`,
      `cleanup-stale-broadcasters`): evaluasi apakah perlu tiap menit atau
      cukup 5 menit.

### P3 — Ketahanan & observabilitas
- [ ] **Guard koneksi DB**: app tidak tahu saat koneksi >50. Tambahkan
      circuit-breaker/backoff di `ChatService` untuk hujan retry.
- [ ] **Rate limit `send-push`/`fanout`**: broadcast ke 500 user = 500 push
      sekaligus. Tambahkan antrean + batch.
- [ ] **`ai-reply` tidak pernah di-stress** (dikecualikan karena biaya).
      Sebelum launch: uji terisolasi dengan budget kecil (10 VU, 5 menit) +
      pasang rate limit per dummy.
- [ ] **Test regresi beban di CI**: simpan ambang (p95 RPC <500ms pada N data)
      sebagai pgTAP/guard agar query baru yang lambat ketahuan sejak awal.

### P4 — Device (kapan sempat)
- [ ] `integration_test/` untuk list 1.000 chat + room ribuan pesan (folder
      belum ada).
- [ ] Frame latency butuh metode baru di MIUI (SurfaceFlinger kosong) —
      alternatif: `PerfProbe` di build bertanda tangan rilis + `dumpsys gfxinfo`
      tidak berlaku untuk Flutter.

## 4. Jejak audit (reproduksibilitas)

- Monitor: `/tmp/stress/monitor.csv` (391 sampel, maks 37 koneksi, 0 lock).
- Skrip: `scripts/stress/` (dicommit).
- Cron di-pause 16 job selama test, **sudah di-restore 16/16 aktif**.
- Akun `stress_*` (300) + 100 pesan kontensi + chat 3.000 pesan: **sudah
  dihapus semua** (verifikasi: `stress_sisa=0`, pesan/chat stress=0).
- DB akhir: users 1.140 (+1 pendaftar nyata selama test), msgs 1.494 (+44
  aktivitas nyata), sisanya sama dengan baseline.
- `ai-reply` TIDAK disentuh sama sekali selama test.

## 5. Aturan untuk test beban berikutnya

1. Selalu backup baseline + pause cron + catat daftar job (untuk restore).
2. Akun sintetis WAJIB prefix `stress_` + hapus + verifikasi setelah selesai.
3. Jangan pernah test `ai-reply` tanpa budget eksplisit (biaya token).
4. Monitor koneksi tiap 5 detik; **abort kalau >50** (dari limit 60).
5. Hasil WAJIB ditulis di dokumen ini (tabel angka, bukan kesan).
