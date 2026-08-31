# Panduan Submit Google Play Console untuk ChatYuk

## Persyaratan
- [ ] Akun developer Google Play dengan akses ke app `com.chatyuk.chatyuk`
- [ ] APK rilis terbaru (`app-apkpure-release.apk`)
- [ ] Data Safety form sudah diisi sesuai panduan

## Langkah Submit
1. **Login ke Google Play Console**
   - URL: https://play.google.com/console/developers
   - Gunakan akun `chatyuk.admin@gmail.com` (atau akun dengan akses)

2. **Pilih aplikasi** `com.chatyuk.chatyuk`
   - Pastikan URL mengandung `developers/8359197228304141922/app/4974318379582736850`

3. **Ke Tab Rilis → Rilis baru**
   - Upload APK: `build/app/outputs/flutter-apk/app-apkpure-release.apk`
   - Pilih track: **Pengujian terbuka** (alpha)
   - Tambahkan catatan rilis

4. **Ke Tab Kebijakan → Keamanan Data**
   - Isi formulir sesuai `play_console_data_safety_guide.md`
   - Verifikasi dengan menjalankan `dart verify_data_collection.dart`

5. **Submit untuk ditinjau**
   - Klik "Kirim untuk ditinjau"
    - Tunggu 1-3 hari untuk persetujuan

## Verifikasi Data Collection
```bash
# Jalankan verifikasi sebelum submit
dart verify_data_collection.dart
flutter clean && flutter build apk --release --flavor apkpure --dart-define=APP_FLAVOR=apkpure
```

## Catatan Penting
- **JANGAN** submit tanpa mengisi Data Safety form
- **JANGAN** ubah versi aplikasi sebelum submit
- **WAJIB** pakai keystore `chatyuk-release-v2.jks`
- **WAJIB** pakai app ID `com.chatyuk.chatyuk`

---

**Status saat ini:**
- [x] APK rilis siap (`131.0MB`)
- [x] Data Safety form siap diisi
- [x] Verifikasi data collection siap
- [ ] Akun developer akses
- [ ] Submit ke Google Play

**Next steps:**
1. Login ke akun developer yang punya akses
2. Isi Data Safety form sesuai panduan
3. Submit APK untuk ditinjau
