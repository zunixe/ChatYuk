# Integration Test ChatYuk

## Kenapa 3 alur kritis ada di `test/flow_*_test.dart`, bukan di sini?

`flutter test integration_test/` di repo ini **memaksa build APK device**
(flutter tool → Gradle `assembleDebug`) dan gagal diodo tanpa emulator +
google-services flavor yang cocok:

```text
No matching client found for package name 'com.chatyuk.chatyuk.dev'
```

Runner CI juga tanpa emulator. Supaya 3 alur kritis tetap terkunci di CI,
mereka ditulis hermetic (service di-mock, tanpa network) dan tinggal di:

| File | Alur |
|---|---|
| `test/flow_chat_test.dart` | Daftar chat → pin → service 1× |
| `test/flow_points_test.dart` | Fitur koin → klaim 5 mnt → service 1× |
| `test/flow_story_test.dart` | Tray story → refresh → 1 author |

Jalankan: `flutter test test/flow_chat_test.dart` (dst.), atau full
`flutter test` seperti biasa.

## Kapan pakai folder ini?

Untuk uji device sungguhan (cold start, scroll 1000 chat, frame latency)
pakai `scripts/stress/device.sh` + `docs/STRESS_TEST.md` Lapis 4 — bukan
`flutter test integration_test/`.

Kalau suatu saat runner CI punya emulator + flavor dev yang sah, pindahkan
kembali 3 file flow ke sini dan tambah `integration_test/app_test.dart`
sebagai entry driver.
