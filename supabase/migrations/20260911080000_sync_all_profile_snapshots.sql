-- Backfill snapshot profil di private_chats.
-- Kasus: umur dummy (mis. laptop 18) tapi participant_ages di chat masih 24 —
-- baris lama yang tidak kena trigger sync (key hilang / edit sebelum trigger
-- ada). Trigger sync_profile_to_chats() sendiri sudah terbukti jalan
-- (tes live: age 27->28 tersebar ke semua chat), jadi cukup backfill + jaga.
-- Rewrite penuh dari profiles = idempoten & aman.
update public.private_chats c
set participant_names = coalesce((
      select jsonb_object_agg(x::text, p.nickname)
      from unnest(c.participants) x join public.profiles p on p.id = x
    ), '{}'::jsonb),
    participant_genders = coalesce((
      select jsonb_object_agg(x::text, p.gender)
      from unnest(c.participants) x join public.profiles p on p.id = x
    ), '{}'::jsonb),
    participant_ages = coalesce((
      select jsonb_object_agg(x::text, p.age)
      from unnest(c.participants) x join public.profiles p on p.id = x
    ), '{}'::jsonb),
    participant_locations = coalesce((
      select jsonb_object_agg(x::text, p.country)
      from unnest(c.participants) x join public.profiles p on p.id = x
    ), '{}'::jsonb);
