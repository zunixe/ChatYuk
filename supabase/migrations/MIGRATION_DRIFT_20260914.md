# Drift History Migration — snapshot 2026-09-14 (RESOLVED)

> Dibuat saat apply `20260914110000_dummy_kind.sql`.
> **STATUS: SELESAI** — drift sudah tidak ada lagi per pengecekan terakhir.

## Hasil akhir

| Metrik | Nilai |
|---|---|
| Migration tercatat di remote (`schema_migrations`) | **248** |
| File migration lokal (`supabase/migrations/*.sql`) | 250 |
| Selisih | 2 |

**2 selisih yang wajar (bukan drift):**
- `20260914120000_room_mute_server.sql` — migration baru (belum di-apply, bukan punya `dummy_kind`).
- `points_v1.sql` — nama tidak match pattern `<timestamp>_name.sql` → selalu di-skip CLI.

## Riwayat

Saat apply `dummy_kind`, `supabase db push` melaporkan **42 migration lokal tidak
ada di history remote** (41 versi lama out-of-order + 1 baru). 41 versi lama itu
kemungkinan di-apply via Management API tanpa insert `schema_migrations`.

**Verifikasi ulang setelahnya:** seluruh 41 versi lama **sudah tercatat** di
`schema_migrations` (drift teratasi — kemungkinan ter-repair otomatis / proses
lain). Total history = 248, sinkron dengan file lokal kecuali 2 item wajar di atas.

## Aturan Tetap Berlaku

1. **JANGAN** `supabase db push --include-all` tanpa cek — replay migration lama
   berisiko drop/recreate objek.
2. Apply migration baru via Management API (pola `APPLIED_VIA_API.md`) + WAJIB
   insert versi ke `schema_migrations`.
3. Timestamp migration **harus unik** — cek dengan `scripts/check_migrations.sh`.

## Cara Regenerate Pengecekan

```bash
# Versi di remote
supabase db query --linked --dns-resolver https --output json \
  "select version from supabase_migrations.schema_migrations order by version" \
  | grep -oE '"version": "[0-9]+"' | grep -oE '[0-9]{14}' | sort > /tmp/remote.txt
# Versi lokal
ls supabase/migrations/*.sql | sed -E 's/.*\/([0-9]{14})_.*/\1/' | sort -u > /tmp/local.txt
# Selisih
comm -23 /tmp/local.txt /tmp/remote.txt
```
