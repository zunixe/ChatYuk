-- P0: kurangi realtime publication high-churn (egress 80%)
-- Keep: private_chats, posts, follows, friend_requests, subscriptions, calls, messages (room) low-churn
do $$
begin
  begin alter publication supabase_realtime drop table public.private_messages; exception when others then null; end;
  begin alter publication supabase_realtime drop table public.room_presence; exception when others then null; end;
  begin alter publication supabase_realtime drop table public.room_signals; exception when others then null; end;
  begin alter publication supabase_realtime drop table public.call_signals; exception when others then null; end;
end $$;
