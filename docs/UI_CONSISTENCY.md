# UI Consistency — Kartu di Bubble Chat

Tujuan: **semua kartu di dalam bubble chat punya margin, lebar, dan posisi jam
yang SAMA**. Keluhan nyata (2026-10-18): kartu KONTAK lebih menjorok ke dalam
(10 padding bubble + 10 padding dalam) dibanding kartu FILE/LOKASI
(4 + 10) → terlihat tidak konsisten.

Berlaku untuk private chat **dan** grup/global room.

## Aturan kanonik (WAJIB diikuti kartu baru)

| Aspek | Nilai | Sumber |
|---|---|---|
| Lebar kartu | `chatMediaWidth(screenW)` = `(screenW * 0.72).clamp(200, 440)` | `lib/core/media/chat_photo_helper.dart` (SATU sumber — jangan hitung sendiri) |
| Padding bubble | `EdgeInsets.all(4)` untuk **semua tipe kartu** | `MessageBubble.isMediaCard` (private), `RoomMessageBubble._isMedia` (room) |
| Padding dalam kartu | 10 kiri/kanan (FileBubble: `fromLTRB(10, 10, 12, 10)`; Kontak: `all(10)`) | `lib/widgets/message/file_bubble.dart`, `lib/widgets/contact_bubble.dart` |
| Baris jam di kartu | `Padding(EdgeInsets.fromLTRB(0, 3, 4, 1))` + rata kanan, gaya `AppText.chatTime` | FileBubble & ContactBubble |
| Tombol aksi dalam kartu | `Row` + `Expanded` → **lebar sama**; teks `maxLines: 1` + `ellipsis` | `lib/widgets/contact_bubble.dart` |
| Tipografi | HANYA token `AppText`/`AppGlyph` (lihat AGENTS.md) | `lib/config/theme.dart` |

**Kartu = tipe yang punya bentuk kotak sendiri**: `image`, `view_once`,
`video`, `location`, `file`, `contact`. Tipe ini WAJIB terdaftar di
`isMediaCard` (private) dan `_isMedia` (room) sehingga bubble memberi padding 4.

## Checklist menambah kartu / tipe pesan baru

1. Daftarkan tipe di **kedua** daftar kartu: `MessageBubble.isMediaCard`
   (`lib/widgets/private_chat_message.dart`) dan `_isMedia`
   (`lib/screens/room_chat/widgets/room_message_bubble.dart`).
2. Widget kartu: root `SizedBox(width: chatMediaWidth(...))`, padding dalam 10,
   baris jam `fromLTRB(0, 3, 4, 1)`.
3. Kalau punya **payload** (mis. `poll`, `contact`): tambahkan tipe ke
   constraint DB **dan** kolom payload ke `privateCols`/`roomCols`
   (`lib/services/chat_stream_session.dart`). Tanpa ini kartu HILANG setelah
   keluar–masuk chat (bug 2026-10-18) karena pesan dari server/cache tak punya
   data definisinya.
4. Tambahkan consumer dedupe pending (`lib/core/chat/pending_confirm.dart`) +
   panggil di private (`private_chat_chat.dart`) & room (`room_chat_room.dart`)
   supaya bubble optimistik tidak tampil DOBEL bersama gema server.
5. Payload ikut cache pesan: field di `MessageModel` (`toMap`/`fromMap`) →
   kartu lengkap di frame pertama tanpa fetch.
6. Tambahkan guard test (lihat `test/ui_consistency_test.dart`) supaya aturan
   di atas tak terdegradasi.

## Status per kartu (2026-10-18)

| Kartu | Lebar | Bubble | Padding dalam | Jam |
|---|---|---|---|---|
| Foto / video / view-once | — (aspect sendiri) | 4 | — | bawaan |
| Lokasi | `chatMediaWidth` | 4 | 10 (di dalam kartu) | `fromLTRB(0,3,4,1)` |
| File | `chatMediaWidth` | 4 | `fromLTRB(10,10,12,10)` | `fromLTRB(0,3,4,1)` |
| **Kontak** | `chatMediaWidth` | **4** | `all(10)` | `fromLTRB(0,3,4,1)` |
| Poll | `chatMediaWidth` | 10 (teks) | 0 | di baris suara (10) |

**Poll = SATU-SATUNYA yang belum dinormalisasi** (kontennya tanpa latar kartu,
padding dalam 0, jadi padding bubble-nya mengikuti teks). Kalau Poll disentuh
suatu saat: beri latar kartu + padding dalam 10, daftarkan sebagai kartu
(padding bubble 4), lalu hapus baris ini dari daftar pengecualian.

## Verifikasi

- `test/ui_consistency_test.dart` — guard sumber: `contact` terdaftar sebagai
  kartu di private & room, `ContactBubble` memakai `chatMediaWidth` + inset jam
  `0,3,4,1`.
- `test/contact_bubble_test.dart` — kartu HP: lebar ≤ `chatMediaWidth`, nama &
  3 nomor panjang tanpa overflow, tombol aksi lebar sama.
