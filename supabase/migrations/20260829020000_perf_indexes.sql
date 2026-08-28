-- Perf untuk jutaan user: index untuk getOnlineUsers & private_chats
create index if not exists idx_private_chats_last_message_at_desc on private_chats (last_message_at desc);
create index if not exists idx_profiles_last_seen_desc on profiles (last_seen desc) where status in ('online','idle');
create index if not exists idx_private_messages_chat_created_desc on private_messages (chat_id, created_at desc);
