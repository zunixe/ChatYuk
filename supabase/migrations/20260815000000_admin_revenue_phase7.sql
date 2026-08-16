-- ChatYuk: Admin Revenue Dashboard (Fase 7)
-- Ringkasan pendapatan platform: potongan gift + ringkasan pencairan.

create or replace function public.admin_revenue_overview()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res jsonb;
begin
  if coalesce(auth.email(), '') != 'zunixe@gmail.com' then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'gift', (
      select jsonb_build_object(
        'cut_total', coalesce(sum(amount), 0),
        'cut_today', coalesce(sum(amount) filter (where created_at >= date_trunc('day', now())), 0),
        'gross_total', coalesce(sum((metadata->>'gross')::int), 0),
        'gross_today', coalesce(sum((metadata->>'gross')::int) filter (where created_at >= date_trunc('day', now())), 0),
        'count_total', count(*),
        'count_today', count(*) filter (where created_at >= date_trunc('day', now())),
        'top_gifts', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'gift', g.gift, 'count', g.cnt, 'cut', g.cut, 'gross', g.gross))
          from (
            select metadata->>'gift' as gift,
                   count(*) as cnt,
                   sum(amount) as cut,
                   sum((metadata->>'gross')::int) as gross
            from platform_revenue
            where source = 'gift_cut'
            group by metadata->>'gift'
            order by sum(amount) desc
            limit 10
          ) g
        ), '[]'::jsonb)
      )
      from platform_revenue where source = 'gift_cut'
    ),
    'withdraw', (
      select jsonb_build_object(
        'pending_count', count(*) filter (where status = 'pending'),
        'pending_payout_idr', coalesce(sum(payout_idr) filter (where status = 'pending'), 0),
        'paid_count', count(*) filter (where status = 'paid'),
        'paid_payout_idr', coalesce(sum(payout_idr) filter (where status = 'paid'), 0),
        'rejected_count', count(*) filter (where status = 'rejected'),
        'rejected_payout_idr', coalesce(sum(payout_idr) filter (where status = 'rejected'), 0)
      )
      from withdrawal_requests
    ),
    'settings', (
      select jsonb_build_object(
        'points_enabled', points_enabled,
        'gift_cut_pct', gift_cut_pct,
        'withdraw_rate_idr', withdraw_rate_idr,
        'withdraw_min_coins', withdraw_min_coins
      )
      from app_settings where id = 'global'
    )
  ) into res;

  return res;
end; $$;
revoke execute on function public.admin_revenue_overview() from public, anon;
grant execute on function public.admin_revenue_overview() to authenticated, service_role;
