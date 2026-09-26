-- Lapis 3: mute story ala IG (benamkan tanpa block).
-- Jalankan: scripts/run_sql_tests.sh story_mute_test.sql
-- Transaksional: data produksi tak berubah (begin/rollback).
begin;
select supabase_tests.begin_tests();

-- Muter = M, author = A (dengan 1 slide aktif).
select supabase_tests.mk_dummy('dd000000-0000-0000-0000-0000000000d1'::uuid, 'TEST Muter');
select supabase_tests.mk_dummy('dd000000-0000-0000-0000-0000000000d2'::uuid, 'TEST Author');
insert into public.stories (author_id, author_name, image_path, visibility, expires_at)
values ('dd000000-0000-0000-0000-0000000000d2', 'TEST Author', 'chat/x.jpg',
  'everyone', now() + interval '1 hour');

-- Konteks: M.
select set_config('request.jwt.claims',
  '{"sub":"dd000000-0000-0000-0000-0000000000d1","email":"m@contoh.id","role":"authenticated"}', false);

-- Baseline: A tampil di tray M, belum dibisukan, unseen.
select supabase_tests.check('baseline: author tampil unseen tak-mute',
  exists (select 1 from jsonb_array_elements(public.story_tray()) t
   where t->>'author_id' = 'dd000000-0000-0000-0000-0000000000d2'
     and (t->>'has_unseen')::boolean
     and not (t->>'muted')::boolean));

-- Mute: flag true + unseen mati + tetap di tray (di belakang).
select public.mute_story_author('dd000000-0000-0000-0000-0000000000d2');
select supabase_tests.check('mute: flag true, unseen mati',
  exists (select 1 from jsonb_array_elements(public.story_tray()) t
   where t->>'author_id' = 'dd000000-0000-0000-0000-0000000000d2'
     and (t->>'muted')::boolean
     and not (t->>'has_unseen')::boolean));

-- Mute diri sendiri ditolak (melempar, tanpa baris).
DO $$
begin
  perform public.mute_story_author('dd000000-0000-0000-0000-0000000000d1');
exception when others then
  null; -- diharapkan: Invalid author
end $$;
select supabase_tests.check('mute diri sendiri → tanpa baris self',
  not exists (select 1 from public.story_mutes
   where muter_id = 'dd000000-0000-0000-0000-0000000000d1'
     and muted_id = 'dd000000-0000-0000-0000-0000000000d1'));

-- Unmute: kembali normal.
select public.unmute_story_author('dd000000-0000-0000-0000-0000000000d2');
select supabase_tests.check('unmute: flag hilang',
  exists (select 1 from jsonb_array_elements(public.story_tray()) t
   where t->>'author_id' = 'dd000000-0000-0000-0000-0000000000d2'
     and not (t->>'muted')::boolean));

select supabase_tests.report() as result;
rollback;
