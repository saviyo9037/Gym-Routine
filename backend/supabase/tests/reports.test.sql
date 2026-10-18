-- Tests for revenue_summary() and dashboard_stats() (service role only).
begin;
select plan(7);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@example.test'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@example.test'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@example.test');

set local role service_role;
select is((select active_subscribers from public.revenue_summary()), 0::bigint, 'empty: zero subscribers');
select is((select mrr_usd from public.revenue_summary()), 0::numeric, 'empty: zero MRR (no fabricated number)');

reset role;
insert into public.entitlements (user_id, is_active, will_renew, expires_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', true, true, now() + interval '20 days'),   -- monthly 10.00
  ('bbbbbbbb-0000-0000-0000-000000000002', true, true, now() + interval '200 days'),  -- yearly 60.00 => 5/mo
  ('cccccccc-0000-0000-0000-000000000003', true, false, now() + interval '5 days');   -- cancelled: not MRR
insert into public.revenuecat_events (event_id, user_id, type, event_timestamp_ms, price, environment, period_type, purchased_at_ms, expiration_at_ms, raw) values
  ('m1', 'aaaaaaaa-0000-0000-0000-000000000001', 'RENEWAL', 2000, 10.00, 'PRODUCTION', 'NORMAL', 0, 30::bigint * 86400000, '{}'),
  ('m0', 'aaaaaaaa-0000-0000-0000-000000000001', 'INITIAL_PURCHASE', 1000, 99.00, 'PRODUCTION', 'NORMAL', 0, 30::bigint * 86400000, '{}'),
  ('y1', 'bbbbbbbb-0000-0000-0000-000000000002', 'INITIAL_PURCHASE', 1000, 60.00, 'PRODUCTION', 'NORMAL', 0, 365::bigint * 86400000, '{}'),
  ('c1', 'cccccccc-0000-0000-0000-000000000003', 'INITIAL_PURCHASE', 1000, 7.00, 'PRODUCTION', 'NORMAL', 0, 30::bigint * 86400000, '{}'),
  ('s1', 'cccccccc-0000-0000-0000-000000000003', 'RENEWAL', 3000, 500.00, 'SANDBOX', 'NORMAL', 0, 30::bigint * 86400000, '{}');

set local role service_role;
select is((select active_subscribers from public.revenue_summary()), 3::bigint, 'counts active entitlements');
select is((select mrr_usd from public.revenue_summary()), 15.00::numeric, 'MRR = latest monthly 10 + yearly 60/12; ignores cancelled and sandbox');
select is((select total_users from public.dashboard_stats()), 3::bigint, 'total users');
select is((select signups_7d from public.dashboard_stats()), 3::bigint, 'signups in 7d');
select is((select dau from public.dashboard_stats()), 0::bigint, 'DAU zero when nobody has last_seen_at');

select * from finish();
rollback;
