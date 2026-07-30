create or replace function public.invite_url(p_token text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  configured_origin text := nullif(rtrim(current_setting('app.settings.app_origin', true), '/'), '');
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{40,128}$' then
    raise exception 'invalid invite token' using errcode = '22023';
  end if;
  if configured_origin is null then
    return '/invite/' || p_token;
  end if;
  if configured_origin !~ '^https://[A-Za-z0-9.-]+(?::[0-9]+)?$'
     and configured_origin !~ '^http://(localhost|127\.0\.0\.1)(?::[0-9]+)?$' then
    raise exception 'invalid app origin' using errcode = '22023';
  end if;
  return configured_origin || '/invite/' || p_token;
end $$;

revoke all on function public.invite_url(text) from public, anon, authenticated;
