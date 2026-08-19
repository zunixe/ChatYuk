-- ============================================================
-- ChatYuk: Pesan Kontak (Hubungi Kami)
-- User mengisi form di ContactScreen → insert ke contact_messages.
-- Admin melihat / menandai terbaca / menghapus via RPC security definer.
-- ============================================================

create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text,
  message text not null,
  user_id uuid references public.profiles(id) on delete set null,
  is_read boolean not null default false
);

alter table public.contact_messages enable row level security;

-- User login boleh mengirim pesan kontak.
drop policy if exists contact_messages_insert on public.contact_messages;
create policy contact_messages_insert on public.contact_messages
  for insert to authenticated
  with check (true);

-- Admin: daftar pesan (pagination, terbaru dulu).
create or replace function public.admin_contact_messages_page(
  p_limit int default 50,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.contact_messages),
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'created_at', m.created_at,
        'name', m.name,
        'message', m.message,
        'user_id', m.user_id,
        'is_read', m.is_read
      ) order by m.created_at desc
    ), '[]'::jsonb)
  )
  into result
  from (
    select * from public.contact_messages
    order by created_at desc
    limit p_limit offset p_offset
  ) m;

  return result;
end;
$$;

-- Admin: tandai terbaca / belum terbaca.
create or replace function public.admin_contact_set_read(
  p_id uuid,
  p_read boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  update public.contact_messages set is_read = p_read where id = p_id;
end;
$$;

-- Admin: hapus pesan.
create or replace function public.admin_contact_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.email(),'') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;
  delete from public.contact_messages where id = p_id;
end;
$$;