# Unit Test ChatYuk

## Kapan dipakai

1. **Sebelum commit** — `flutter test` + `flutter analyze` harus hijau
   (0 error, 0 warning). `strings_test` sengaja digagalkan duluan kalau ada
   hardcode Indonesia / `fontSize` numerik / `height` manual.
2. **Sesudah ubah kode** — ubah model/provider/utils → jalankan file test
   terkait dulu (`flutter test test/models_test.dart`), baru full suite.
3. **Saat refactor** — `MessageModel`, `PrivateChatInfo`, `rt_resilient`,
   `MessageStore` dikunci test (roundtrip, trim 500, backoff). Test merah =
   refactor merusak.
4. **CI / sesi AI berikutnya** — jaring pengaman lintas-sesi: pelanggaran
   bilingual/tipografi ketahuan tanpa harus baca AGENTS.md.

## Perintah

```bash
flutter test                              # full suite
flutter test test/models_test.dart        # per-file saat iterasi cepat
flutter test --coverage                   # + gate CI: providers/services/models >= 60%
flutter analyze                           # 0 error, 0 warning
```

## Isi test

| File | Yang dikunci |
|---|---|
| `strings_test.dart` | bilingual `strings.dart`, tanpa hardcode ID di `Text`/`tooltip`, tanpa `fontSize`/`height` manual di luar `lib/config` |
| `widget_test.dart` | token `AppText`/`AppGlyph`/`StoryText`, `AdminGate.isRealAdmin` |
| `providers_test.dart` | `NavProvider`, `LocaleProvider`, `ThemeProvider` |
| `models_test.dart` | privasi hapus `MessageModel`, default `User/Room/Story`, `PrivateChatInfo` |
| `utils_test.dart` | `BoundedCache`, `snakeToCamel`, `formatBytes`, `dateChipLabel` |
| `chat/timeline_provider_test.dart` | delegasi pin/mute/archive, offline-safe feed |
| `message_store_test.dart` | roundtrip, window terbaru, trim 500, kv |
| `rt_resilient_test.dart` | retry/backoff/cancel/dispose |
| `auth_room_di_test.dart` | DI `AuthProvider`/`RoomProvider` (injeksi service + skip autoInit), state awal |
| `flow_chat_test.dart` | alur kritis: pin dari daftar → service 1× (hermetic, ikut CI) |
| `flow_points_test.dart` | alur kritis: klaim online 5 mnt dari UI → service 1× |
| `flow_story_test.dart` | alur kritis: refresh tray → 1 author tampil |
| `widgets/call_overlay_test.dart` | smoke mount widget |

## Batasan

`AuthProvider`/`RoomProvider` sudah DI-ready (`{authService/service/chatService,
autoInit}`) dan dikunci `auth_room_di_test.dart` untuk konstruksi + state
awal. Logika dalam `_init`/`_listenAuthState`/subscription realtime belum
di-unit-test — butuh fake stream + `fake_async` sebelum bisa dikunci penuh.
`PointsProvider` sudah DI (`{service}`) + `points_provider_test.dart`.
