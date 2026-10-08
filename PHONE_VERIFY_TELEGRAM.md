# Verifikasi Nomor HP via Telegram + Badge Emas

Dokumen desain & catatan implementasi fitur **verifikasi nomor HP lewat bot
Telegram** untuk ChatYuk, beserta **badge terverifikasi berwarna emas** yang
menggantikan centang biru lama (`is_registered`).

> **RAHASIA**: token bot TIDAK ditulis di dokumen ini. Nilainya hanya disimpan
> sebagai Supabase secret (`TELEGRAM_BOT_TOKEN`). Yang tercatat di sini hanya
> **nama** secret.

---

## 1. Ringkasan

User mengisi nomor HP di **Pengaturan › Akun › Nomor HP** (sudah ada). Nomor
langsung tersimpan (unverified). Untuk mendapat **badge emas**, user membuka bot
Telegram `@chatyuk_verify_bot`, menekan tombol **"Bagikan nomor saya"**, dan bot
mencocokkan nomor kontak dengan nomor yang didaftarkan. Bila cocok →
`profiles.phone_verified_at` diisi → badge emas muncul.

Alur yang dipilih: **B** (user membuka bot & membagikan kontak; bukan OTP yang
diketik manual).

---

## 2. Keputusan (terkunci)

| # | Keputusan |
|---|---|
| 1 | Alur **B**: buka bot Telegram → tombol "Bagikan nomor" → bot cocokkan |
| 2 | Nomor **disimpan dulu** (unverified) sampai verifikasi sukses |
| 3 | Verifikasi → **badge gradien emas** |
| 4 | Rate limit **3×/jam**, link/token berlaku **15 menit** |
| 5 | Cocokkan nomor via **normalisasi digit** (buang non-digit) |
| 6 | **2 edge function** terpisah: `telegram-verify` (JWT) + `telegram-webhook` (publik) |
| 7 | Badge user lain lewat **RPC baru** `verified_uids` (tidak menyentuh `get_online_users`/`nearby_users`) |
| 8 | Badge tampil di **Online, Nearby, Chat, Komentar** (+ Profil) |
| 9 | Badge emas **menggantikan** centang biru `is_registered` |
| 10 | Token `/start <token>` disimpan di sesi webhook (`telegram_chat_id`) |
| 11 | Ganti nomor → **reset** `phone_verified_at` (harus verifikasi ulang) |
| 12 | Set secret via **Supabase CLI** (sudah login & link) |
| 13 | Token bot **tidak direset** setelah fitur (keputusan pemilik) |

---

## 3. Bot Telegram

- **Username**: `chatyuk_verify_bot`
- **Nama tampilan**: `ChatYuk Verify`
- **Bot id**: `8497198859` (diverifikasi via `getMe`)

### Cara membuat bot (BotFather) — untuk referensi

1. Telegram → cari `@BotFather` (centang biru) → **START**.
2. `/newbot` → isi nama tampilan → isi username (wajib akhiri `bot`).
3. BotFather membalas **token** (`<angka>:<huruf-panjang>`). Simpan sebagai secret.
4. (Opsional) `/setdescription`, `/setuserpic`, `/setcommands`:
   ```
   start - Verifikasi nomor HP kamu
   status - Cek status verifikasi
   ```
5. Verifikasi: `GET https://api.telegram.org/bot<TOKEN>/getMe`.

---

## 4. Alur

```
[App] Pengaturan › Akun › Nomor HP
   │  simpan nomor (profiles.phone, phone_verified_at = null)
   ▼
[App] tombol "Verifikasi via Telegram"
   │  POST telegram-verify {action:"start"}   (JWT user)
   ▼
[RPC phone_verify_start]  → token 32-hex, expires_at = now()+15m, rate limit 3/jam
   │  balikin deep-link: https://t.me/chatyuk_verify_bot?start=<token>
   ▼
[App] buka deep-link via url_launcher → Telegram
   │  user tekan START
   ▼
[Bot] /start <token> → telegram-webhook simpan telegram_chat_id + kirim
   │  tombol "Bagikan nomor saya" (request_contact)
   ▼
[Bot] message.contact → telegram-webhook
   │  RPC phone_verify_confirm(token, phone, chat_id)
   │    - normalisasi digit; cocokkan dengan profiles.phone
   │    - set phone_verifications.status='verified'
   │    - set profiles.phone_verified_at = now()
   ▼
[App] polling telegram-verify {action:"status"} → verified → badge emas muncul
```

---

## 5. Skema DB

Migrasi: `supabase/migrations/<timestamp>_phone_telegram_verify.sql`.

### Kolom baru

```sql
alter table public.profiles
  add column if not exists phone_verified_at timestamptz;
```

### Tabel `phone_verifications`

| kolom | tipe | keterangan |
|---|---|---|
| `id` | bigserial PK | |
| `uid` | uuid → profiles(id) | pemilik |
| `phone` | text | nomor yang didaftarkan (ternormalisasi) |
| `token` | text unique | token sekali-pakai (32 hex) |
| `telegram_chat_id` | bigint | diisi webhook saat `/start <token>` |
| `status` | text | `pending` / `verified` / `expired` / `failed` |
| `attempts` | int | jumlah percobaan |
| `created_at` | timestamptz | |
| `expires_at` | timestamptz | `created_at + 15 menit` |
| `verified_at` | timestamptz | |

### RPC

| RPC | Akses | Fungsi |
|---|---|---|
| `phone_verify_start()` | authenticated (SECURITY DEFINER, `auth.uid()`) | rate limit 3/jam; buat token; kembalikan `{token, expires_at}` |
| `phone_verify_status()` | authenticated | kembalikan `{phone, verified, verified_at}` |
| `phone_verify_confirm(p_token, p_phone, p_chat_id)` | service_role | cocokkan nomor; set verified + `phone_verified_at` |
| `verified_uids(p_uids uuid[])` | authenticated | daftar uid yang `phone_verified_at is not null` |

### Trigger

- Pada `profiles.phone` berubah → `phone_verified_at = null` (keputusan 11).

### RLS

- `phone_verifications`: user hanya boleh `select` baris miliknya; tulis hanya lewat RPC.
- **Tidak menyentuh fungsi FROZEN** (`scripts/frozen_functions.txt`).

---

## 6. Edge Functions

| Function | `verify_jwt` | Peran |
|---|---|---|
| `telegram-verify` | `true` | Client path: `{action:"start"}` → deep-link; `{action:"status"}` |
| `telegram-webhook` | `false` | Terima update Telegram; cek header `x-telegram-bot-api-secret-token` |

`telegram-webhook` menangani:
- `/start <token>` → simpan `telegram_chat_id`, kirim tombol share-contact.
- `message.contact` → `phone_verify_confirm(token, phone, chat_id)` → balas sukses/gagal.

---

## 7. Secrets (nama saja — nilai TIDAK di dokumen ini)

| Secret | Isi |
|---|---|
| `TELEGRAM_BOT_TOKEN` | token dari BotFather |
| `TELEGRAM_WEBHOOK_SECRET` | string acak (pembanding header webhook) |
| `TELEGRAM_BOT_USERNAME` | `chatyuk_verify_bot` |

Set via CLI:

```bash
supabase secrets set TELEGRAM_BOT_TOKEN="<token>"
supabase secrets set TELEGRAM_WEBHOOK_SECRET="$(openssl rand -hex 32)"
supabase secrets set TELEGRAM_BOT_USERNAME="chatyuk_verify_bot"
```

---

## 8. Webhook Telegram

Daftarkan (sekali, setelah deploy):

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://<project-ref>.supabase.co/functions/v1/telegram-webhook" \
  -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```

Verifikasi:

```bash
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
```

`pending_update_count` kecil & tanpa `last_error_message` = sehat.

---

## 9. Perubahan App

| File | Perubahan |
|---|---|
| `lib/widgets/verified_badge.dart` | **BARU** — badge centang gradien emas |
| `lib/providers/riverpod/verified_provider.dart` | **BARU** — cache `Set<String>` via `verified_uids` |
| `lib/providers/riverpod/phone_verification_provider.dart` | **BARU** — `start()` + polling `status()` |
| `lib/config/strings.dart` | string bilingual verifikasi + badge |
| `lib/widgets/phone_edit_dialog.dart` | tawaran "Verifikasi via Telegram" + buka deep-link |
| `lib/screens/account_screen.dart` | badge emas di baris Nomor HP |
| `lib/screens/online_users_screen.dart` | badge (ganti `Icons.verified` biru) |
| `lib/screens/nearby/widgets/nearby_card.dart` | badge |
| `lib/screens/private_chats_screen.dart` | badge di list chat |
| `lib/screens/private_chat_screen.dart` | badge di header |
| `lib/widgets/private_chat_message.dart` | badge di nama pengirim bubble |
| `lib/widgets/post_card.dart` | badge di komentar |
| `lib/screens/profile_screen.dart`, `lib/screens/user_info_screen.dart` | badge |

---

## 10. Langkah Uji

1. **SQL**: panggil `phone_verify_start()` (sebagai user) → cek row `pending` + token.
2. **Bot**: buka `t.me/chatyuk_verify_bot?start=<token>` → tekan "Bagikan nomor".
3. **DB**: cek `profiles.phone_verified_at` terisi & `phone_verifications.status='verified'`.
4. **App**: badge emas muncul (Online/Nearby/Chat/Komentar).
5. **Negatif**: nomor berbeda → tidak verified; token kedaluwarsa → gagal; >3×/jam → rate limited.
6. **Ganti nomor** → badge hilang (harus verifikasi ulang).

---

## 11. Checklist Verifikasi

- [ ] `flutter analyze` → 0 error / 0 warning
- [ ] `flutter test`
- [ ] `bash scripts/check_screen_boundary.sh` → 0 screen import services
- [ ] `scripts/check_migrations.sh` (bila ada)
- [ ] Uji end-to-end di HP Xiaomi (24129PN74G)
