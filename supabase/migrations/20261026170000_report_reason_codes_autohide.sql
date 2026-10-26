-- LAPORAN PESAN BER-ALASAN + AUTO-HIDE (permintaan user 2026-10-26)
--
-- MASALAH: `reports` lama hanya (reporter_id, reported_id, reason free-text)
-- — tidak menunjuk PESAN mana, tanpa status/aksi, dan tidak ada tindak lanjut.
-- Dilaporkan berkali-kali pun tidak terjadi apa pun.
--
-- Perbaikan:
--   * reports + message_id, room_id, reason_code, status, actioned_by/at.
--   * unique (reporter_id, message_id) → satu user satu laporan per pesan.
--   * RPC report_room_message(): insert laporan; bila >=3 PELAPOR BERBEDA
--     untuk pesan yang sama → pesan otomatis disembunyikan (`is_deleted`)
--     + catat `admin_alerts`.
--   * Laporan lama (tanpa message_id) tetap sah (kolom nullable).
--
-- SAFE: aditif (kolom nullable di reports + RPC baru + 1 fungsi trigger tidak
--       ada). Tidak mengubah policy/RLS/tabel lain yang sudah ada.
--       Fitur terdampak: lapor pesan (tambahan; lapor user tetap jalan).

alter table public.reports
  add column if not exists message_id text,
  add column if not exists room_id    text,
  add column if not exists reason_code text
    check (reason_code is null or reason_code in
           ('porn', 'violence', 'spam', 'scam', 'other')),
  add column if not exists status text not null default 'open'
    check (status in ('open', 'actioned', 'dismissed')),
  add column if not exists actioned_by uuid,
  add column if not exists actioned_at timestamptz;

-- Satu laporan per (pelapor, pesan). Laporan lama (message_id null) tidak
-- terpengaruh karena index parsial.
create unique index if not exists reports_one_per_message
  on public.reports (reporter_id, message_id)
  where message_id is not null;

create index if not exists reports_message_idx
  on public.reports (message_id) where message_id is not null;

-- ── RPC lapor pesan ────────────────────────────────────────────────────────
create or replace function public.report_room_message(
  p_message_id text,
  p_reason_code text,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me        uuid := auth.uid();
  v_room    text;
  v_sender  uuid;
  v_reporters integer;
  v_hidden  boolean := false;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if coalesce(p_message_id, '') = '' then
    raise exception 'message_required' using errcode = '22023';
  end if;

  select m.room_id, m.sender_id into v_room, v_sender
    from public.messages m where m.id::text = p_message_id;
  if v_room is null then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;
  if v_sender = me then
    return jsonb_build_object('ok', false, 'error', 'own_message');
  end if;

  insert into public.reports
    (reporter_id, reported_id, reason, message_id, room_id, reason_code)
  values (me, v_sender, coalesce(p_note, ''), p_message_id, v_room,
          coalesce(nullif(p_reason_code, ''), 'other'))
  on conflict (reporter_id, message_id) where message_id is not null do update
    set reason_code = excluded.reason_code,
        reason = excluded.reason,
        status = 'open',
        created_at = now();

  -- Auto-hide: >=3 PELAPOR BERBEDA untuk pesan yang sama.
  select count(distinct r.reporter_id) into v_reporters
    from public.reports r
   where r.message_id = p_message_id
     and r.status <> 'dismissed';

  if v_reporters >= 3 then
    update public.messages set is_deleted = true
     where id::text = p_message_id and coalesce(is_deleted, false) = false;
    if found then
      v_hidden := true;
      insert into public.admin_alerts (kind, severity, message, detail)
      values ('reported_media', 'high',
              'Pesan disembunyikan otomatis (>=3 laporan)',
              jsonb_build_object('message_id', p_message_id,
                                 'room_id', v_room,
                                 'reporters', v_reporters));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reporters', v_reporters,
                            'auto_hidden', v_hidden);
end;
$function$;

revoke execute on function public.report_room_message(text, text, text) from public, anon;
grant execute on function public.report_room_message(text, text, text) to authenticated;

-- ── Admin/moderator: tandai laporan selesai ───────────────────────────────
create or replace function public.resolve_message_reports(
  p_message_id text,
  p_action     text default 'actioned'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me   uuid := auth.uid();
  v_room text;
  v_country text;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select m.room_id into v_room from public.messages m where m.id::text = p_message_id;
  if v_room is null then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;
  select r.country into v_country from public.rooms r where r.id = v_room;

  if not (public.is_chatyuk_admin(me)
          or public.is_country_moderator(v_country, me)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.reports
     set status = case when p_action = 'dismissed' then 'dismissed' else 'actioned' end,
         actioned_by = me, actioned_at = now()
   where message_id = p_message_id and status = 'open';

  insert into public.moderator_actions
    (scope, scope_value, uid, message_id, action, note)
  values ('country', coalesce(v_country, ''), me, p_message_id,
          'dismiss_report', p_action);

  return jsonb_build_object('ok', true);
end;
$function$;

revoke execute on function public.resolve_message_reports(text, text) from public, anon;
grant execute on function public.resolve_message_reports(text, text) to authenticated;
