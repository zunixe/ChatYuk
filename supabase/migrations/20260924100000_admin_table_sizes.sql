-- Breakdown ukuran tabel untuk panel admin (Ringkasan → Database 71MB diklik).
-- Fungsi BARU (tidak menyentuh fungsi FROZEN mana pun).
-- Cepat: hanya baca katalog (pg_total_relation_size + reltuples estimasi),
-- tanpa seq-scan, tanpa ukuran per-baris.
create or replace function public.admin_table_sizes(p_limit int default 30)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  result jsonb;
  v_db bigint;
  v_lim int := greatest(coalesce(p_limit, 30), 1);
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;

  select pg_database_size(current_database()) into v_db;

  select jsonb_build_object(
    'db_bytes', v_db,
    'tables', coalesce((
      select jsonb_agg(t)
      from (
        select jsonb_build_object(
          'schema', n.nspname,
          'table', c.relname,
          'total_bytes', pg_total_relation_size(c.oid),
          'table_bytes', pg_relation_size(c.oid),
          'index_bytes', pg_indexes_size(c.oid),
          'rows_est', c.reltuples::bigint
        ) as t
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where c.relkind in ('r', 'p')
          and n.nspname not in ('pg_catalog', 'information_schema')
        order by pg_total_relation_size(c.oid) desc
        limit v_lim
      ) s
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$fn$;

revoke execute on function public.admin_table_sizes(int) from public, anon;
grant execute on function public.admin_table_sizes(int) to authenticated, service_role;
