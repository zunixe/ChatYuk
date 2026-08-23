create or replace function public.call_history_insert() returns trigger as $$
declare
  cid text;
  cname text;
  cgender text;
  dur int;
  stext text;
  txt text;
  exists_cnt int;
begin
  if new.status not in ('ended','failed') then return new; end if;
  if old.status = new.status then return new; end if;
  select case when new.caller_id::text < new.callee_id::text then new.caller_id::text || '_' || new.callee_id::text else new.callee_id::text || '_' || new.caller_id::text end into cid;
  select nickname, gender into cname, cgender from public.profiles where id = new.caller_id;
  if cname is null then cname := 'Unknown'; end if;
  if cgender is null then cgender := 'unknown'; end if;
  if new.answered_at is not null and new.ended_at is not null then dur := extract(epoch from (new.ended_at - new.answered_at))::int; else dur := 0; end if;
  if dur < 0 then dur := 0; end if;
  if new.status = 'ended' and dur > 0 then stext := 'Call ended (' || (dur/60)::int || ':' || lpad((dur%60)::text,2,'0') || ')';
  elsif new.status = 'ended' then stext := 'Call ended';
  else stext := 'Call failed'; end if;
  if new.call_type = 'video' then txt := '📹 ' || stext; else txt := '📞 ' || stext; end if;
  select count(*) into exists_cnt from public.private_messages where chat_id = cid and type='call' and text = txt and created_at > now() - interval '10 seconds';
  if exists_cnt > 0 then return new; end if;
  insert into public.private_messages (chat_id, sender_id, sender_name, sender_gender, text, type, image_data) values (cid, new.caller_id, coalesce(cname,'Unknown'), coalesce(cgender,'unknown'), txt, 'call', '');
  return new;
  exception when others then return new;
end;
$$ language plpgsql security definer;
drop trigger if exists call_history_trigger on public.calls;
create trigger call_history_trigger after update on public.calls for each row execute function public.call_history_insert();
