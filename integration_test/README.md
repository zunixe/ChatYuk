# Integration Test ChatYuk

> **STATUS: TIDAK DIPAKAI.** Folder ini hanya berisi dokumen ini — tidak ada
> file test. Dev-dependency `integration_test` sudah dihapus dari
> `pubspec.yaml` karena merusak build rilis (lihat bagian bawah).

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

## Sebelum menghidupkan folder ini lagi

Dev-dep `integration_test` **sudah dihapus** dari `pubspec.yaml`. Jangan
tambahkan kembali tanpa memperbaiki dua hal dulu:

1. **Flavor `dev` butuh `google-services.json` sendiri** — tanpa itu build
   gagal `No matching client found for package name 'com.chatyuk.chatyuk.dev'`.
2. **Plugin registrant rilis** — dev-dep ini menyuntikkan plugin
   `dev.flutter.plugins.integration_test` ke `GeneratedPluginRegistrant.java`,
   tapi Gradle release tidak menyertakannya →
   `package dev.flutter.plugins.integration_test does not exist`.
   Perlu flavor/varian khusus test, bukan dev-dep global.

Selain itu runner CI harus punya emulator (sekarang `ubuntu-latest` tanpa KVM).
