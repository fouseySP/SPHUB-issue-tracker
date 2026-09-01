-- SPHUB Tracker — Supabase setup
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.

create table if not exists public.issues (
  id text primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.issues enable row level security;

-- Only signed-in (authenticated) users can read or write issues.
-- Visitors without a valid login get nothing.
drop policy if exists "authenticated can read"   on public.issues;
drop policy if exists "authenticated can insert" on public.issues;
drop policy if exists "authenticated can update" on public.issues;
drop policy if exists "authenticated can delete" on public.issues;

create policy "authenticated can read"   on public.issues for select to authenticated using (true);
create policy "authenticated can insert" on public.issues for insert to authenticated with check (true);
create policy "authenticated can update" on public.issues for update to authenticated using (true) with check (true);
create policy "authenticated can delete" on public.issues for delete to authenticated using (true);
