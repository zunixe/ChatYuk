-- ============================================================
-- ChatYuk Timeline — BACKFILL dimensi foto post lama
--
-- Post yang dibuat SEBELUM 20260927000000 (posts_image_dims) tidak
-- menyimpan image_w/image_h → feed jatuh ke fallback (layout kurang
-- presisi). Migration ini mengisi dimensi dari file Storage.
--
-- ⚠️ CARA APPLY: nilai dimensi di bawah dibaca dari file Storage asli
--    (bucket chat-photos public) via skrip Python di
--    tmp_capture/backfill_dims.py. Query UPDATE memakai VALUES sehingga
--    bisa di-apply via Supabase Management API (CLI db push hang).
--
-- Idempoten: hanya menyentuh baris yang masih image_w=0 (safe re-apply
-- untuk post baru yang sudah punya dimensi sendiri).
-- ============================================================

update posts as p set
  image_w    = v.w,
  image_h    = v.h,
  image_dims = v.d
from (values
  ('220abf97-2d29-405e-9287-c6952bb6ebec'::uuid, 1200, 1200, '[{"w":1200,"h":1200}]'::jsonb),
  ('580878e4-468c-434f-bb3f-e453f896e36e'::uuid, 1200, 1600, '[{"w":1200,"h":1600}]'::jsonb),
  ('c2c5b258-538d-4cd7-a1c0-2cec8104d551'::uuid, 1200, 2680, '[{"w":1200,"h":2680}]'::jsonb),
  ('eebd357d-f911-4787-a14f-8582300c262b'::uuid, 1200, 1498, '[{"w":1200,"h":1498}]'::jsonb),
  ('04c03d69-9e1d-446b-8ccb-bf8cea26dab4'::uuid, 1200, 2133, '[{"w":1200,"h":2133}]'::jsonb),
  ('4561470c-f0bc-4034-bbb9-a3ce9cd33ef3'::uuid, 1200, 1825, '[{"w":1200,"h":1825}]'::jsonb),
  ('e1954222-fcf9-4665-a961-6c3e8314ff64'::uuid, 1200, 1600, '[{"w":1200,"h":1600}]'::jsonb)
) as v(id, w, h, d)
where p.id = v.id and p.image_w = 0;
