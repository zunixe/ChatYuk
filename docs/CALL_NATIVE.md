# CALL NATIVE — UI panggilan sistem (ConnectionService / CallKit)

> Cara ChatYuk menampilkan panggilan masuk sebagai **UI panggilan sistem**
> (layar kunci, headset, Bluetooth, Android Auto) — gaya WhatsApp — tanpa
> memindahkan WebRTC ke native.

Terakhir diperbarui: 2026-09-19.

---

## Prinsip

**Media tetap 100% di Dart.** `CallSession` (`lib/services/call_service.dart`)
memegang `RTCPeerConnection`, renderer, TURN, dan signaling. Native **hanya**
menangani:

1. Menampilkan ring panggilan masuk (UI sistem, bukan layar Dart).
2. Meneruskan aksi pengguna: jawab / tolak / akhiri.

Ini mungkin karena `CallSession.init()` (mulai WebRTC) baru dipanggil
**setelah** pengguna menekan terima (`incoming_call_screen.dart` → `_accept`).

---

## Lapisan

```
Dart                                    Native (Android)
────────────────────────────────────    ──────────────────────────────
CallUi (abstract)                       CallConnectionService  ← Telecom
 ├─ CallUiStub      (iOS/web/test)       └─ CallConnection
 └─ CallUiChannel   (Android)                  ↑ onCreateIncomingConnection
      ↕ MethodChannel                         │
      'com.chatyuk.chatyuk/call_ui'     CallUiBridge  ← channel
                                         ChartyukMessagingService
                                          (push FCM saat app MATI)
```

### File

| File | Peran |
|---|---|
| `lib/services/call/call_ui.dart` | Interface `CallUi` + `CallUiStub` (no-op) |
| `lib/services/call/call_ui_channel.dart` | Jembatan MethodChannel + buffer aksi dingin |
| `lib/services/call/call_ui_factory.dart` | `createCallUi()` — Android channel, lain stub |
| `android/.../call/CallConnection.kt` | Satu `Connection` (answer/reject/disconnect) |
| `android/.../call/CallConnectionService.kt` | `ConnectionService` + PhoneAccount SELF_MANAGED |
| `android/.../call/CallUiBridge.kt` | Jembatan channel Dart ↔ native |
| `android/.../call/ChartyukMessagingService.kt` | Push `type=call` saat app mati |

### Protocol channel

| Arah | Method | Payload |
|---|---|---|
| Dart→native | `showIncoming` | `{callId, callerName, callType}` |
| Dart→native | `setConnected` | `{callId}` |
| Dart→native | `dismiss` | `{callId}` |
| native→Dart | `onAccept` | `callId` |
| native→Dart | `onDecline` | `callId` |
| native→Dart | `onEnd` | `callId` |

---

## Alur

### App hidup — panggilan masuk
1. Realtime `calls` insert → `CallProvider._onIncoming`.
2. Push `IncomingCallScreen` (Dart) **dan** `callUi.showIncoming` (native).
3. `usesSystemUi == true` → layar Dart **tidak** memutar ringtone (sistem yang
   ring — cegah nada dering dobel).
4. Pengguna jawab dari UI sistem → `CallConnection.onAnswer` →
   `CallUiBridge.deliverToDart('onAccept')` → `CallProvider.bindIncomingScreen`
   → `_accept()` (alur Dart yang sama).
5. `startSession` → `callUi.setConnected` (UI sistem → in-call).
6. `clearSession` → `callUi.dismiss`.

### App mati — panggilan masuk
1. FCM data-only `type=call` diterima `ChartyukMessagingService`.
2. `super.onMessageReceived` **selalu** dipanggil (notifikasi biasa tetap jalan).
3. `CallUiBridge.getInstance() == null` (app mati) → `CallConnectionService.
   startIncoming` → `TelecomManager.addNewIncomingCall`.
4. Pengguna jawab → `CallConnection.onAnswer` → tidak ada bridge → buka
   `MainActivity` dengan extra `accept` + `callId`.
5. `MainActivity.handleCallIntent` → `deliverToDart` (ditunda 600 ms agar
   engine siap) → buffer `CallUiChannel` → `_onSystemAccept`.
6. Tanpa layar → `CallProvider` ambil row dari DB → buka `IncomingCallScreen`
   dengan `autoAccept: true` → `_accept()`.

### Race cold start
Aksi native bisa tiba sebelum `CallProvider` selesai memasang callback.
`CallUiChannel` menyimpan aksi di `_pending` dan memutarnya begitu callback
terpasang (`_flushPending`). Tanpa ini, jawab dari layar kunci saat app baru
dibuka bisa hilang.

---

## Aturan (jangan dilanggar)

1. **`ChartyukMessagingService` WAJIB memanggil `super.onMessageReceived`
   di semua jalur** — kalau tidak, notifikasi chat/mention/follow mati saat
   app di background.
2. **Jangan pindahkan WebRTC ke native** — `CallConnection` hanya UI.
3. **Satu sumber aksi**: tombol sistem diteruskan ke `IncomingCallScreen`
   (`bindIncomingScreen`), bukan implementasi kedua.
4. **`usesSystemUi`** menentukan siapa yang memutar ringtone.
5. `firebase-messaging` **harus** ada di `android/app/build.gradle.kts`
   (classpath aplikasi), bukan hanya di plugin — kalau tidak,
   `ChartyukMessagingService` gagal compile.
6. Jangan `cancel()`+`show()` notif call (MIUI meninggalkan notif hantu) —
   `call_ended` meng-update notif yang sama (lihat `main.dart`).

---

## iOS (belum diimplementasi)

`createCallUi()` mengembalikan `CallUiStub` di iOS — perilaku = layar Dart
sekarang (ring lewat `IncomingCallScreen` + `audioplayers`). Kode tetap
kompilasi iOS.

Untuk CallKit penuh nanti:
1. Tambah `ios/Runner/CallKitProvider.swift` (`CXProvider` + `CXProviderDelegate`).
2. Registrasi channel yang **sama** (`com.chatyuk.chatyuk/call_ui`) — Dart
   tidak perlu berubah.
3. **Wajib PushKit + VoIP push** (APNs cert VoIP) — VoIP push tidak bisa
   digantikan FCM biasa; butuh edge function pengirim VoIP push baru.
4. `CallUiStub` untuk iOS diganti `CallUiChannel` bila channel sudah ada.

Karena repo ini Android-only (iOS tidak pernah di-build untuk distribusi),
CallKit iOS = pekerjaan + backend terpisah.

---

## Uji

- **Unit** (`test/call_ui_test.dart`): routing method channel, buffer aksi
  dingin, integrasi provider (accept id cocok/lain, unbind, end tanpa sesi).
- **Device** (manual, wajib karena Telecom tidak bisa di-emulator penuh):
  1. App hidup: panggil → ring sistem muncul → jawab dari layar kunci.
  2. App hidup: tolak dari sistem → status `declined` di DB.
  3. App mati (swipe dari recents): panggil → ring sistem → jawab → app
     terbuka & tersambung.
  4. Bluetooth/headset: jawab dari tombol headset.
  5. Caller batalkan saat ring → ring sistem berhenti.
  6. Regresi: notifikasi chat/mention tetap muncul saat app di background
     (memastikan `super.onMessageReceived` jalan).
