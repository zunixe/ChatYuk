-- ============================================================
-- Isi profession per dummy + perbaikan generator cerita harian
--
-- MASALAH (temuan live 2026-09-14):
-- Generator story (ai-daily-life/index.ts:182) HANYA membaca
-- dummy_accounts.ai_persona->>'profession'. Field itu KOSONG di
-- semua dummy → prompt story tidak menyebut pekerjaan sama sekali,
-- lalu baris 201 memaksa "Senin-Jumat = hari kerja kantoran".
-- Akibat nyata:
--   - MbakSari (asisten rumah tangga) → cerita "kerjakan proposal"
--   - Sarah (22 th, ceria/anime)       → cerita "urus data karyawan"
--   - agoy (Argentina, fans bola)      → "Data analyst kantor fintech"
--
-- Perbaikan:
--   1) Isi profession yang BENAR per dummy (di bawah).
--   2) ai-daily-life: profession → fallback personality/extra_prompt,
--      dan aturan hari kerja MENGIKUTI profesi (bukan paksa kantoran).
-- ============================================================

-- ── 1. Profession per dummy (dari persona masing-masing) ──
update public.dummy_accounts d
   set ai_persona = coalesce(d.ai_persona, '{}'::jsonb)
                    || jsonb_build_object('profession', v.prof)
  from (values
    -- CS resmi aplikasi: jangan dibuatkan cerita harian kantoran;
    -- profesi tetap diisi agar generator punya konteks bila terpanggil.
    ('Admin Chatyuk',  'Customer service resmi aplikasi ChatYuk (duduk di kantor ChatYuk, melayani user)'),
    ('agoy',           'Pekerja lepas remote / freelance; orang Argentina (Buenos Aires) yang tinggal di Indonesia, hobi utama nonton bola'),
    ('aqila',          'Programmer / ngoding; keseharian anak kost di Jakarta (pekerjaan resminya RAHASIA - jangan sebut perusahaan/kantornya)'),
    ('BinorMuda',      'Ibu rumah tangga yang juga buka usaha online shop kecil-kecilan di Jakarta'),
    ('Dhanu',          'Pedagang / pemilik usaha kecil di Banda Aceh (jualan sembako & kelontong)'),
    ('Dr Nara',        'Psikolog; menerima sesi konseling di ruang praktiknya'),
    ('HardwareExpert', 'Arsitek hardware / engineer yang kerja riset dan desain di lab'),
    ('Kang Modal',     'Analis investasi; bekerja memantau pasar saham dan kripto'),
    ('MbakSari',       'Asisten rumah tangga (ART) yang bekerja di rumah majikan di Jakarta - mengurus rumah tangga, bersih-bersih, masak, dan belanja rumah'),
    ('Sarah',          'Mahasiswi di Denpasar, kuliah + kerja paruh waktu di kafe/toko dekat kampus'),
    ('SoftwareExpert', 'Insinyur perangkat lunak senior; kerja ngoding dan review arsitektur sistem'),
    ('Admin',          'Customer service resmi aplikasi ChatYuk')
  ) as v(nick, prof)
 where d.nickname = v.nick;

-- ── 2. Verifikasi ──
select p.nickname, d.ai_persona->>'profession' as profession
from public.dummy_accounts d
join public.profiles p on p.id = d.uid
order by p.nickname;
