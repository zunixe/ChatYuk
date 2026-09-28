-- Tambah kuota bandwidth + label paket ke admin_storage_stats.
--
-- Konteks: user Pro menanyakan batas bandwidth — pemakaian egress LIVE tidak
-- diekspos API mana pun (hanya terlihat di dashboard Supabase → Usage), jadi
-- yang bisa ditampilkan adalah BATAS kuotanya. Pro = 250 GB egress
-- (+ 250 GB cached egress terpisah, per supabase.com/pricing).
-- Body disalin utuh dari 20260928160000; yang ditambah HANYA 2 key output
-- (quota_bandwidth_bytes, plan). Bukan FROZEN.
create or replace function public.admin_storage_stats()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_db bigint;
  v_total_files bigint;
  v_total_bytes bigint;
  v_msg_day bigint; v_msg_week bigint; v_msg_month bigint;
  v_sig_day bigint; v_sig_week bigint; v_sig_month bigint;
  v_stor_day bigint; v_stor_week bigint; v_stor_month bigint;
  v_reg_day bigint; v_reg_week bigint; v_reg_month bigint;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select pg_database_size(current_database()) into v_db;

  select coalesce(count(*),0), coalesce(sum((metadata->>'size')::bigint),0)
    into v_total_files, v_total_bytes
    from storage.objects;

  -- Pertumbuhan pesan privat (teks + gambar base64).
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_day from private_messages where created_at > now() - interval '1 day';
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_week from private_messages where created_at > now() - interval '7 days';
  select coalesce(sum(length(coalesce(text,'')) + length(coalesce(image_data,''))),0)
    into v_msg_month from private_messages where created_at > now() - interval '30 days';

  -- Pertumbuhan sinyal call (payload JSON).
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_day
    from call_signals where created_at > now() - interval '1 day';
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_week
    from call_signals where created_at > now() - interval '7 days';
  select coalesce(sum(octet_length(payload::text)),0) into v_sig_month
    from call_signals where created_at > now() - interval '30 days';

  -- Pertumbuhan file storage.
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_day
    from storage.objects where created_at > now() - interval '1 day';
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_week
    from storage.objects where created_at > now() - interval '7 days';
  select coalesce(sum((metadata->>'size')::bigint),0) into v_stor_month
    from storage.objects where created_at > now() - interval '30 days';

  -- Pertumbuhan registrasi email.
  select count(*) into v_reg_day from profiles
   where is_registered = true and created_at > now() - interval '1 day';
  select count(*) into v_reg_week from profiles
   where is_registered = true and created_at > now() - interval '7 days';
  select count(*) into v_reg_month from profiles
   where is_registered = true and created_at > now() - interval '30 days';

  select jsonb_build_object(
    'db_bytes',            v_db,
    'storage_bytes',       v_total_bytes,
    'storage_files',       v_total_files,
    'total_bytes',         v_db + v_total_bytes,
    'quota_db_bytes',      8589934592,       -- 8 GB (paket PRO)
    'quota_storage_bytes', 107374182400,     -- 100 GB (paket PRO)
    'quota_bandwidth_bytes', 268435456000,   -- 250 GB egress (paket PRO)
    'plan',                'pro',
    'growth', jsonb_build_object(
      'day',   jsonb_build_object('messages', v_msg_day,  'signals', v_sig_day,  'storage', v_stor_day,  'registrations', v_reg_day),
      'week',  jsonb_build_object('messages', v_msg_week, 'signals', v_sig_week, 'storage', v_stor_week, 'registrations', v_reg_week),
      'month', jsonb_build_object('messages', v_msg_month,'signals', v_sig_month,'storage', v_stor_month,'registrations', v_reg_month)
    )
  ) into result;

  return result;
end;
$fn$;
