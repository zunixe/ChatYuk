-- Trigger notify_call dipisah dari baseline (tabel calls dibuat di 20260819150000)
drop trigger if exists calls_notify_trigger on public.calls;
create trigger calls_notify_trigger
  after insert on public.calls
  for each row execute function public.notify_call();

