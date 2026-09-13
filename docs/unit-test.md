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
flutter test                              # full suite (~91 test)
flutter test test/models_test.dart        # per-file saat iterasi cepat
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
| `widgets/call_overlay_test.dart` | smoke mount widget |

## Batasan

`AuthProvider`/`RoomProvider`/`PointsProvider` belum di-unit-test —
konstruktornya langsung menyentuh Supabase/Firebase/timer. Butuh refactor
DI (inject service) dulu sebelum bisa di-test.
