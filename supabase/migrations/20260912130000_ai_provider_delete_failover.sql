-- admin_ai_provider_delete: hapus provider AKTIF otomatis memindahkan
-- status aktif ke provider lain dulu (failover), supaya tombol Hapus
-- selalu berfungsi dari UI. Pengecualian: satu-satunya provider yang
-- tersisa TIDAK boleh dihapus (dummy butuh fallback) → PROVIDER_LAST_ACTIVE.
-- Prioritas pengganti: yang punya api_key, lalu updated_at terbaru.
create or replace function public.admin_ai_provider_delete(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_active boolean;
  v_next text;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select p.is_active into v_active
  from public.ai_provider_config p where p.id = p_id;
  if v_active is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;
  if v_active then
    select p.id into v_next
    from public.ai_provider_config p
    where p.id <> p_id
    order by (p.api_key is not null) desc, p.updated_at desc nulls last
    limit 1;
    if v_next is null then
      raise exception 'PROVIDER_LAST_ACTIVE';
    end if;
    update public.ai_provider_config set is_active = true where id = v_next;
  end if;
  delete from public.ai_provider_config where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

revoke execute on function public.admin_ai_provider_delete(text) from public, anon;
grant execute on function public.admin_ai_provider_delete(text) to authenticated, service_role;
