-- ============================================================
-- ChatYuk Timeline — BACKFILL BlurHash untuk post LAMA
--
-- Post yang dibuat SEBELUM 20261017130000 (posts_blurhash) belum punya
-- image_blurhashes → feed memakai alas #1E1E1E. Migration ini mengisi hash
-- dari foto Storage (bucket chat-photos, public read).
--
-- Hash dihitung dengan ENCODER APLIKASI (`lib/core/media/blurhash.dart`,
-- 32px, komponen 4×3) agar konsisten dengan post baru.
--
-- Idempoten: hanya menyentuh baris yang image_blurhashes-nya masih kosong.
--
-- ⚠️ CARA APPLY: Management API (lihat APPLIED_VIA_API.md).
-- ============================================================

update posts as p
set image_blurhashes = v.bh
from (values
  ('0043caed-24c0-41d7-842a-aeef1a465198'::uuid, '["LFJ*eo?bfi-;0$X9Rja~Xlx]tRae"]'::jsonb),
  ('04c03d69-9e1d-446b-8ccb-bf8cea26dab4'::uuid, '["LnJj[0M_IUWAT}RiRPR%tTfPs-oK"]'::jsonb),
  ('0690adbf-1ba0-41d6-8cd2-febf9bc1b874'::uuid, '["LfLqFL-=?u%g~pxvskt7%#R*IUoc"]'::jsonb),
  ('1b92a70b-f50f-485f-9b92-7871a7653909'::uuid, '["LHBWrUH?Ezoy.mWBR-k9pwxZnTX8"]'::jsonb),
  ('220abf97-2d29-405e-9287-c6952bb6ebec'::uuid, '["LbO3;BD$.6?bW@t7%1R-~pRkRjRj"]'::jsonb),
  ('24a0a856-1e4c-4357-a1e9-cebbc14c0aef'::uuid, '["LeHT?9~Ux[-oxsNHIpxZofNHRks."]'::jsonb),
  ('2ffdd260-a790-400d-9839-175121aa0503'::uuid, '["LMHxj8yFIAxU*0%hMxRO%ibxRPRi"]'::jsonb),
  ('3496b9b0-eefc-459b-890f-ab5e3db9094a'::uuid, '["LlN]|N%2x^%LIxa#adRk4moaIURP"]'::jsonb),
  ('35ba483d-459d-415c-81f2-214f9327a2b6'::uuid, '["LNI;@l~Vxan-%NIUt7bENyD*M{tQ"]'::jsonb),
  ('4561470c-f0bc-4034-bbb9-a3ce9cd33ef3'::uuid, '["LFAcMONJ9[M|0#xav~t6M_aexba}"]'::jsonb),
  ('52d8e503-6143-4ae0-b9ef-913cf8a0b363'::uuid, '["LcO3@As:%#xu_NozIAof9FayV@Rj"]'::jsonb),
  ('580878e4-468c-434f-bb3f-e453f896e36e'::uuid, '["L9E.65?HTK.9?bVsEMxu9Z4T9FxG"]'::jsonb),
  ('6547363c-ab9c-41c7-9eb3-a7ac511b0eb1'::uuid, '["LSJQyQacD%wg_4Ioxtt7kEIUS#oy"]'::jsonb),
  ('a3ea78c1-9498-456b-b9e4-4340eb07670a'::uuid, '["LMJG.?O]xu-U~D%MWYsA0K,UI:NG"]'::jsonb),
  ('c0ed0565-8897-40e0-bc97-413fe712526b'::uuid, '["L6FYGM-V^g?Z~Jxsoz4:wH-p-WkD"]'::jsonb),
  ('c2c5b258-538d-4cd7-a1c0-2cec8104d551'::uuid, '["LA8q7^-oRkNb_NofV[s;_3ofW.of"]'::jsonb),
  ('c72dde96-17aa-4c6b-b1fc-61ae24a2f96e'::uuid, '["LVF$I#xFRjR+xEf*WXf60JS2e:xZ"]'::jsonb),
  ('cc7b82a7-33a3-49fa-919b-d2408a1f5004'::uuid, '["LhHd%0}@RPS#9Fah%2V@ozRkbHof"]'::jsonb),
  ('e49dd8d7-43e1-4256-828e-08e25c90616e'::uuid, '["LYIE^W-;?b%M~otRWBfPbcjYIURj"]'::jsonb),
  ('eebd357d-f911-4787-a14f-8582300c262b'::uuid, '["LYAn.YozH=WqyZofR4WDiujZV@j["]'::jsonb),
  ('f62e8c0f-7a4e-47ee-a437-ac4292c95d6f'::uuid, '["LEG[m3ivx@ozpcoIxZWs_N%2RjE1"]'::jsonb),
  ('fd7adac2-5a70-4458-8f3d-5cd47bc2e132'::uuid, '["L8AJZ[M[x?^l0LxbjURooO%MoIW."]'::jsonb)
) as v(id, bh)
where p.id = v.id
  and (p.image_blurhashes is null or p.image_blurhashes = '[]'::jsonb);
