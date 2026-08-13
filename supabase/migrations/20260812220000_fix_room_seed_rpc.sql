-- ============================================================
-- ChatYuk: Fix seeding room setelah hardening rooms RLS
-- Hardening sebelumnya membuat rooms INSERT/UPDATE hanya admin.
-- Akibatnya seedCountryRooms() (upsert dari client user biasa)
-- ditolak RLS → room list kosong saat app dibuka.
--
-- Solusi: seeding room lewat RPC security definer (bisa dipanggil
-- user biasa), sementara policy rooms INSERT/UPDATE tetap dibatasi
-- admin agar user tidak bisa edit room seenaknya.
-- ============================================================

-- RPC untuk seeding room per negara (idempotent).
-- security definer → bypass RLS, aman karena hanya upsert room
-- kategori standar (tidak ada data sensitif).
create or replace function public.seed_rooms(p_country text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_country is null or p_country = '' then
    return;
  end if;

  insert into public.rooms (id, name, description, icon, country, category, "order")
  values
    (p_country || '_general',    'General',    'Chat umum',         '💬', p_country, 'general',    1),
    (p_country || '_curhat',     'Curhat',     'Cerita & curhat',   '💭', p_country, 'curhat',     2),
    (p_country || '_pertemanan', 'Pertemanan', 'Cari teman baru',   '🤝', p_country, 'pertemanan', 3),
    (p_country || '_teknologi',  'Teknologi',  'Diskusi tech',      '💻', p_country, 'teknologi',  4),
    (p_country || '_gaming',     'Gaming',     'Main & bahas game', '🎮', p_country, 'gaming',     5),
    (p_country || '_musik',      'Musik',      'Sharing musik',     '🎵', p_country, 'musik',      6),
    (p_country || '_film',       'Film & TV',  'Review film',       '🎬', p_country, 'film',       7),
    (p_country || '_joke',       'Joke & Meme','Bikin ngakak',      '😂', p_country, 'joke',       8),
    (p_country || '_belajar',    'Belajar',    'Diskusi belajar',   '📚', p_country, 'belajar',    9),
    (p_country || '_flirt',      'Flirt',      'Ngobrol asyik',     '💘', p_country, 'flirt',      10)
  on conflict (id) do nothing;
end;
$$;

revoke execute on function public.seed_rooms(text) from public, anon;
grant execute on function public.seed_rooms(text) to anon, authenticated;
