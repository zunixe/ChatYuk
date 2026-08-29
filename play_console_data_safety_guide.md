# Google Play Console - Data Safety Form Guide for ChatYuk

## Step 1: Ringkasan (Summary)
- **Nama aplikasi**: ChatYuk
- **Paket**: com.chatyuk.chatyuk
- **Jenis aplikasi**: Aplikasi

## Step 2: Pengumpulan dan keamanan data (Data collection & security)
- **Data pengguna dikumpulkan**: Ya
- **Data pengguna dibagikan**: Tidak
- **Data pengguna dihapus saat**: Pengguna menghapus akun atau otomatis setelah 30 hari tidak aktif

## Step 3: Jenis data (Data types)
### Wajib diisi:
- [x] **Perangkat atau ID lainnya**
  - **Dikumpulkan**: Ya
  - **Deskripsi**: ID perangkat unik untuk identifikasi pengguna dan analitik
  - **Tujuan**: Identifikasi pengguna, personalisasi fitur, analisis performa
  - **Data dihapus saat**: User menghapus akun atau otomatis setelah 90 hari tidak aktif

### Opsional (tidak dicentang):
- [ ] Kontak
- [ ] Lokasi
- [ ] Pesan
- [ ] Foto/video
- [ ] Audio
- [ ] Kalender
- [ ] File
- [ ] Teks dan gambar yang diketik

## Step 4: Penggunaan dan penanganan data (Usage & handling)
### Bagaimana data digunakan:
- [x] Identifikasi pengguna unik untuk fitur personalisasi chat
- [x] Mengumpulkan metrik penggunaan untuk optimasi performa
- [x] Mengamankan akun dengan verifikasi perangkat
- [ ] Menampilkan iklan
- [ ] Menyesuaikan konten iklan

### Data dibagikan dengan:
- [x] Tidak dibagikan ke pihak ketiga
- [ ] Google
- [ ] Perusahaan atau organisasi lain

## Step 5: Pratinjau (Preview)
Verifikasi semua pernyataan akurat sebelum mengirim.

---

**Catatan penting:**
- Formulir ini berdasarkan implementasi aktual di kode ChatYuk
- Semua deklarasi sesuai dengan `DeviceInfoService.installId()` dan penggunaan data
- Tidak ada data pengguna yang dikumpulkan tanpa deklarasi

