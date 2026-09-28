# Insiden: "Notifikasi online mati" — token FCM terhapus (2026-09-28)

## Gejala
- Notifikasi **"X sedang online"** tidak muncul lagi (dulu muncul).
- Berlaku luas — bukan cuma 1 device. Pesan/call pun ikut terdampak
  (semua push lewat jalur token yang sama).

## Fakta yang menyesatkan (server SEHAT)
Dicek langsung ke DB live via Management API:
- Cron `chatyuk-outbox-worker` **aktif** (`* * * * *`), `outbox` pending = 0.
- Trigger `notify_contact_online_trigger` **ada** & berjalan — outbox terus
  terisi baris `type=online`.
- Edge `send-push` v65, `outbox-worker` v3 → **ACTIVE**.

Jadi fitur notifikasi **bukan** yang rusak. Masalahnya di **token FCM**.

## Akar masalah (terbukti, diukur per-token via send-push)
Menembak `send-push` ke setiap token device, hasil (13 token aktif):

| Hasil FCM | Jumlah | Arti |
|---|---|---|
| ✅ 200 OK | 2 | Token hidup, project benar |
| ❌ 404 UNREGISTERED | 7 | Token basi (app install ulang / rotate) |
| ❌ 403 SENDER_ID_MISMATCH | 4 | Token dari Firebase project LAMA `chatyuk-8470e` |

**~85% token mati.** Ditambah: **banyak device aktif (`last_seen_at` baru)
tapi `fcm_token` KOSONG** (33 device aktif, hanya 1–2 punya token).

### Penyebab #1 — token kosong di-write ke DB (bug client) ← INTI
`AuthProvider.updateFcmToken()` (lib/providers/auth_provider.dart):
```dart
final token = await FirebaseMessaging.instance.getToken();
await _auth.updateFcmToken(token);   // token bisa NULL
```
`getToken()` **bisa mengembalikan null secara wajar** (FCM belum siap, jaringan
flaky, HP baru). Loop retry hanya mengulang saat **exception**, bukan saat
**null**. Lalu `AuthService.updateFcmToken(null)` menulis `''`:
```dart
final t = token ?? '';
await _sb.rpc('update_device_fcm_token', params: {... 'p_token': t});
```
RPC `update_device_fcm_token` **menimpa** `fcm_token` tanpa syarat →
token yang tadinya **VALID terhapus**. Device jadi "aktif tapi tanpa token"
→ `user_fcm_tokens()` mengembalikan kosong → notif tidak terkirim.

### Penyebab #2 — token basi/mismatch menumpuk
- 404: token lama tak pernah dibersihkan (`is_active` tetap true).
- 403: device masih daftar token dari project Firebase **lama**
  (`chatyuk-8470e`); app sekarang kirim via `chatyuk-7c9e4` → ditolak.

### Penyebab #3 — drop diam (fase outbox F)
`outbox-worker` v3 memperlakukan **4xx = permanen** → baris di-mark `sent_at`
(dibuang) tanpa terkirim. Jadi di DB tampak "terkirim", padahal notif tak ada —
membuat masalah tidak terlihat.

## Perbaikan
### Kode (diterapkan, commit a0c7fd7)
`lib/providers/auth_provider.dart` → `updateFcmToken()`:
```dart
final token = await FirebaseMessaging.instance.getToken();
if (token == null || token.isEmpty) {
  await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
  continue;                 // JANGAN tulis token kosong
}
await _auth.updateFcmToken(token);
```
Hanya token **berisi** yang disimpan. Jalur OFF
(`setNotificationsEnabled(false)`) tetap menulis `''` secara **sengaja**
(mematikan push) — jangan ubah itu.

### Data (produksi)
- Token mati (404/403) dipurge (auto-clean `send-push` + `purge_fcm_token`).
- Sisa: hanya 1–2 device dengan token valid. Device lain menunggu re-register
  saat app dibuka dengan build yang sudah diperbaiki.

## Pencegahan (cek SEBELUM rilis bila menyentuh FCM token)
- [ ] **JANGAN pernah** menulis token kosong/null ke `profiles.fcm_token` /
      `user_devices.fcm_token` kecuali memang user mematikan notifikasi.
- [ ] `getToken()` null = keadaan NORMAL → retry, bukan dianggap "tidak ada
      token lalu tulis `''`".
- [ ] Device dengan build lama (project Firebase lama) WAJIB update app agar
      `getToken()` ambil token dari project baru `chatyuk-7c9e4`.
- [ ] Bila "notif mati": cek dulu **validitas token** (`send-push` per token),
      bukan trigger/cron — server sering sehat, token yang mati.

## Catatan proses (kesalahan saat menangani)
Saat membersihkan token, pengujian per-token dijalankan dengan **banyak koneksi
paralel** → menghabiskan slot koneksi langsung Postgres (`db`/`rest`/`auth`
UNHEALTHY, `pooler`/`realtime` sehat). Project di-restart via Management API
untuk memulihkan. **Pelajaran:** bersihkan token lewat **satu query / RPC**,
JANGAN flood koneksi; restart HANYA darurat (data tidak hilang, tapi
mengganggu). Lain kali: tanya dulu sebelum aksi berdampak produksi.
