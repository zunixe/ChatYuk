-- ============================================================
-- Sync organisasi monitor chat admin (PIN + KATEGORI/folder) antar perangkat.
--
-- MASALAH: `admin_chat_org.dart` menyimpan pin & kategori HANYA di
-- SharedPreferences lokal per HP. Kategori dibuat di 1 HP (mis. Xiaomi)
-- TIDAK muncul di HP admin lain (Redmi) — bukan bug, memang lokal.
--
-- SOLUSI: simpan di server, satu baris global, sync ke semua HP admin.
-- Tabel RLS enabled TANPA policy (deny semua) — hanya service_role &
-- RPC security-definer (admin-guarded) yang boleh akses. Ini alat kerja
-- admin, bukan data produk; tidak bocor ke user biasa.
--
-- Bukan fungsi FROZEN. CARA APPLY: Management API.
-- ============================================================

create table if not exists public.admin_chat_org (
  id text primary key default 'global',
  pinned_chat_ids text[] not null default '{}',
  category_list text[] not null default '{}',
  -- chatId → nama kategori (chatId tanpa entri = belum berkategori).
  category_map jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.admin_chat_org enable row level security;

-- Seed baris global (idempoten).
insert into public.admin_chat_org (id) values ('global')
on conflict (id) do nothing;

-- ── GET: baca organisasi (guard admin) ──
create or replace function public.admin_get_chat_org()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v public.admin_chat_org;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  select * into v from public.admin_chat_org where id = 'global';
  if v is null then
    return jsonb_build_object(
      'pinned_chat_ids', '[]'::jsonb,
      'category_list', '[]'::jsonb,
      'category_map', '{}'::jsonb
    );
  end if;
  return jsonb_build_object(
    'pinned_chat_ids', to_jsonb(coalesce(v.pinned_chat_ids, '{}')),
    'category_list', to_jsonb(coalesce(v.category_list, '{}')),
    'category_map', coalesce(v.category_map, '{}'::jsonb)
  );
end;
$function$;

-- ── SET: tulis organisasi (guard admin) ──
create or replace function public.admin_set_chat_org(
  p_pinned text[] default null,
  p_categories text[] default null,
  p_map jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v public.admin_chat_org;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com'
     and auth.role() != 'service_role' then
    raise exception 'Unauthorized';
  end if;
  insert into public.admin_chat_org (id) values ('global')
  on conflict (id) do nothing;
  update public.admin_chat_org
  set pinned_chat_ids = coalesce(p_pinned, pinned_chat_ids),
      category_list = coalesce(p_categories, category_list),
      category_map = coalesce(p_map, category_map),
      updated_at = now()
  where id = 'global'
  returning * into v;
  return jsonb_build_object(
    'pinned_chat_ids', to_jsonb(coalesce(v.pinned_chat_ids, '{}')),
    'category_list', to_jsonb(coalesce(v.category_list, '{}')),
    'category_map', coalesce(v.category_map, '{}'::jsonb)
  );
end;
$function$;

revoke execute on function public.admin_get_chat_org() from public, anon, authenticated;
revoke execute on function public.admin_set_chat_org(text[], text[], jsonb) from public, anon, authenticated;
grant execute on function public.admin_get_chat_org() to authenticated, service_role;
grant execute on function public.admin_set_chat_org(text[], text[], jsonb) to authenticated, service_role;
