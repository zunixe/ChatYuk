// Supabase Edge Function: terms
// Halaman Syarat & Ketentuan (Terms of Service) ChatYuk — dipakai sebagai
// "Website Utama" / terms URL pada integrasi iPaymu (production validation).

Deno.serve(async (_req) => {
  const html = `<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Syarat & Ketentuan — ChatYuk</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.7; color: #333; max-width: 720px; margin: 0 auto; padding: 32px 20px 80px; }
  h1 { font-size: 26px; color: #1a1a2e; border-bottom: 2px solid #2196F3; padding-bottom: 12px; }
  h2 { font-size: 19px; color: #1a1a2e; margin-top: 28px; }
  p, li { font-size: 15px; }
  .updated { color: #888; font-size: 13px; margin-top: -8px; }
  ul { padding-left: 24px; }
</style>
</head>
<body>
  <h1>Syarat & Ketentuan — ChatYuk</h1>
  <p class="updated">Terakhir diperbarui: 16 Agustus 2026</p>

  <h2>1. Layanan</h2>
  <p>ChatYuk adalah aplikasi obrolan (chat) yang menyediakan fitur pesan, room, serta sistem koin virtual untuk fitur berbayar (gift, subscribe, dan top-up).</p>

  <h2>2. Koin Virtual</h2>
  <p>Koin ChatYuk adalah mata uang virtual yang dibeli melalui penyedia pembayaran resmi (iPaymu). Koin yang dibeli tidak dapat ditukar kembali menjadi uang tunai, kecuali koin "earned" yang memenuhi syarat pencairan (KYC) sesuai ketentuan aplikasi.</p>

  <h2>3. Akun Pengguna</h2>
  <p>Pengguna bertanggung jawab atas keamanan akunnya. Penyalahgunaan (spam, penipuan, atau konten terlarang) dapat mengakibatkan pemblokiran akun tanpa pemberitahuan sebelumnya.</p>

  <h2>4. Konten</h2>
  <p>Pengguna dilarang mengunggah konten yang melanggar hukum, SARA, pornografi, atau hak kekayaan intelektual pihak lain.</p>

  <h2>5. Pembayaran</h2>
  <p>Seluruh transaksi pembayaran diproses oleh penyedia pembayaran pihak ketiga. ChatYuk tidak menyimpan data kartu kredit atau kredensial pembayaran pengguna.</p>

  <h2>6. Perubahan Ketentuan</h2>
  <p>ChatYuk berhak mengubah syarat & ketentuan ini sewaktu-waktu. Perubahan akan diberitahukan melalui aplikasi.</p>

  <h2>7. Kontak</h2>
  <p>Pertanyaan dapat diajukan melalui email: zunixe@gmail.com</p>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
});
