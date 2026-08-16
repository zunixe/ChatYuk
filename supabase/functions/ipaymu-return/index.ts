// Supabase Edge Function: ipaymu-return
// Halaman sederhana yang ditampilkan saat user kembali dari iPaymu
// (returnUrl / cancelUrl). Menampilkan tombol "Kembali ke ChatYuk" yang
// mencoba membuka app via deep link (chatyuk://), lalu fallback.
// Dipakai sebagai returnUrl & cancelUrl di ipaymu-create agar tidak error
// (domain https://chatyuk.app tidak ter-resolve).

const DEEP_LINK = 'chatyuk://login-callback?topup=done';

function esc(s: string) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const status = url.searchParams.get('status') || 'done';
  const title = status === 'success' ? 'Pembayaran Selesai' : 'Kembali ke ChatYuk';
  const msg = status === 'success'
    ? 'Pembayaran kamu sedang diproses. Koin akan masuk otomatis setelah terkonfirmasi.'
    : 'Transaksi dibatalkan atau belum selesai.';

  const html = `<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  body { font-family: system-ui, sans-serif; background: #1E1E2E; color: #fff;
         display: flex; flex-direction: column; align-items: center; justify-content: center;
         min-height: 100vh; margin: 0; text-align: center; padding: 24px; }
  .btn { display: inline-block; margin-top: 20px; padding: 14px 28px; background: #2ECC71;
         color: #fff; border-radius: 24px; text-decoration: none; font-weight: 700; }
  .hint { color: #aaa; margin-top: 12px; font-size: 14px; }
</style>
</head>
<body>
  <h1>${title}</h1>
  <p>${msg}</p>
  <a class="btn" href="${esc(DEEP_LINK)}">Kembali ke ChatYuk</a>
  <p class="hint">Jika tidak otomatis terbuka, buka aplikasi ChatYuk secara manual.</p>
  <script>
    var frame = document.createElement('iframe');
    frame.style.display = 'none';
    frame.src = "${esc(DEEP_LINK)}";
    document.body.appendChild(frame);
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
});
