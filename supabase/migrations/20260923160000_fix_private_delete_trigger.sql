-- Fix delete private chat selalu gagal: trigger scrub_reply_snapshot_private
-- membandingkan replied_to_id (text) dengan new.id (bigint) tanpa cast →
-- Postgres error "operator does not exist: text = bigint", seluruh UPDATE
-- is_deleted=true di-rollback → client selalu terima 0 baris / exception.
-- Room aman (messages.replied_to_id bigint). Backfill di migrasi asal sudah
-- pakai ::text, hanya trigger yang kelewat.
create or replace function public.scrub_reply_snapshot_private()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_deleted = true and (old.is_deleted is distinct from true) then
    update public.private_messages pm
    set replied_to_text = null,
        replied_to_sender_name = null
    where pm.replied_to_id = new.id::text;
  end if;
  return new;
end; $$;

drop trigger if exists scrub_reply_snapshot_private_trg on public.private_messages;
create trigger scrub_reply_snapshot_private_trg
after update on public.private_messages
for each row execute function public.scrub_reply_snapshot_private();
