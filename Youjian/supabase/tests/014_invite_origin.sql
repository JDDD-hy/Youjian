begin;
select plan(4);

select set_config('app.settings.app_origin', '', true);
select is(
  public.invite_url(repeat('A', 43)),
  '/invite/' || repeat('A', 43),
  'missing app origin returns a safe relative invite URL'
);

select set_config('app.settings.app_origin', 'https://jddd-hy.github.io/', true);
select is(
  public.invite_url(repeat('B', 43)),
  'https://jddd-hy.github.io/invite/' || repeat('B', 43),
  'configured HTTPS origin is used without a duplicate slash'
);

select throws_ok(
  $$select public.invite_url('short')$$,
  '22023',
  'invalid invite token',
  'invalid invite tokens are rejected'
);

select set_config('app.settings.app_origin', 'http://evil.example', true);
select throws_ok(
  $$select public.invite_url(repeat('C', 43))$$,
  '22023',
  'invalid app origin',
  'non-HTTPS non-loopback origins are rejected'
);

select * from finish();
rollback;
