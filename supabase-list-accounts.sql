-- SPHUB Tracker — list all login accounts with their effective role
-- Editors see every auth account in the tracker's Team panel. Safe to re-run.

create or replace function public.list_accounts()
returns table(email text, role text)
language sql stable security definer set search_path = public as $$
  select u.email::text, coalesce(r.role, 'viewer')
  from auth.users u
  left join roles r on r.email = lower(u.email)
  where public.my_role() = 'editor'
  order by u.email;
$$;
grant execute on function public.list_accounts() to authenticated;
