-- SPHUB Tracker — editor/viewer roles + CM-reported issues pool
-- Run after supabase-setup.sql and supabase-notifications.sql. Safe to re-run.

-- Accounts listed here as 'editor' get full control.
-- Any signed-in account NOT listed is a viewer: read-only + can submit reports.
create table if not exists public.roles (
  email text primary key,
  role text not null default 'editor'
);
alter table public.roles enable row level security;
-- no client policies: clients learn their own role only via the my_role() RPC

insert into roles (email, role) values
  ('y.alqufaidi@pantheriq.sa', 'editor'),
  ('a.binobaid@pantheriq.sa', 'editor'),
  ('r.elshafei@pantheriq.sa', 'editor')
on conflict (email) do update set role = excluded.role;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select role from roles where email = lower(auth.jwt()->>'email')), 'viewer');
$$;
grant execute on function public.my_role() to authenticated;

-- Issues raised by viewers (CMs), pending team review.
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  title text not null,
  description text not null default '',
  reporter_name text not null default '',
  kind text not null default 'bug', -- bug | enhancement
  status text not null default 'pending', -- pending | accepted | dismissed
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
drop policy if exists "authenticated read reports" on public.reports;
drop policy if exists "authenticated submit reports" on public.reports;
drop policy if exists "editors update reports" on public.reports;
drop policy if exists "editors delete reports" on public.reports;
create policy "authenticated read reports" on public.reports
  for select to authenticated using (true);
create policy "authenticated submit reports" on public.reports
  for insert to authenticated with check (status = 'pending');
create policy "editors update reports" on public.reports
  for update to authenticated using (public.my_role() = 'editor') with check (true);
create policy "editors delete reports" on public.reports
  for delete to authenticated using (public.my_role() = 'editor');

-- Tighten issue and member writes to editors (reads stay open to all signed-in).
drop policy if exists "authenticated can insert" on public.issues;
drop policy if exists "authenticated can update" on public.issues;
drop policy if exists "authenticated can delete" on public.issues;
create policy "editors can insert" on public.issues
  for insert to authenticated with check (public.my_role() = 'editor');
create policy "editors can update" on public.issues
  for update to authenticated using (public.my_role() = 'editor') with check (public.my_role() = 'editor');
create policy "editors can delete" on public.issues
  for delete to authenticated using (public.my_role() = 'editor');

drop policy if exists "authenticated all" on public.members;
create policy "authenticated read members" on public.members
  for select to authenticated using (true);
create policy "editors write members" on public.members
  for insert to authenticated with check (public.my_role() = 'editor');
create policy "editors update members" on public.members
  for update to authenticated using (public.my_role() = 'editor') with check (public.my_role() = 'editor');
create policy "editors delete members" on public.members
  for delete to authenticated using (public.my_role() = 'editor');
