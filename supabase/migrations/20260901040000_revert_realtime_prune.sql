-- Revert P0 realtime prune — private_messages & room_presence kembali ke publication
-- Karena client masih pakai postgres_changes (belum migrasi ke broadcast), drop bikin delay 30s.
-- Broadcast migration akan dikerjakan terpisah dengan fanout Edge Function yang lebih matang.
do $$
begin
  begin alter publication supabase_realtime add table public.private_messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.room_presence; exception when others then null; end;
  begin alter publication supabase_realtime add table public.room_signals; exception when others then null; end;
  begin alter publication supabase_realtime add table public.call_signals; exception when others then null; end;
end $$;
