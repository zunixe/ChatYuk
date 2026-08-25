-- Hapus duplikat device lama yang terbuat akibat install_id UUID per-install.
-- Simpan hanya row terbaru per (user_id, brand, model) biar 1 HP = 1 row di panel.
-- Setelah patch ANDROID_ID, duplikat tidak akan muncul lagi.

with ranked as (
  select id, row_number() over (
    partition by user_id, lower(brand), lower(model)
    order by last_seen_at desc nulls last, created_at desc
  ) as rn
  from public.user_devices
)
delete from public.user_devices
where id in (select id from ranked where rn > 1);
