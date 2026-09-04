-- SPHUB Tracker — manage account privileges from the app
-- Run after supabase-roles.sql. Safe to re-run.

-- Editors may read and manage the roles list from the tracker UI.
drop policy if exists "editors read roles" on public.roles;
drop policy if exists "editors insert roles" on public.roles;
drop policy if exists "editors update roles" on public.roles;
drop policy if exists "editors delete roles" on public.roles;
create policy "editors read roles" on public.roles
  for select to authenticated using (public.my_role() = 'editor');
create policy "editors insert roles" on public.roles
  for insert to authenticated with check (public.my_role() = 'editor');
create policy "editors update roles" on public.roles
  for update to authenticated using (public.my_role() = 'editor') with check (public.my_role() = 'editor');
create policy "editors delete roles" on public.roles
  for delete to authenticated using (public.my_role() = 'editor');

-- Lockout guard: the last editor can never be demoted or removed.
create or replace function public.protect_last_editor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'DELETE' and old.role = 'editor')
     or (tg_op = 'UPDATE' and old.role = 'editor' and new.role <> 'editor') then
    if (select count(*) from roles where role = 'editor') <= 1 then
      raise exception 'Cannot remove the last editor account';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_protect_last_editor on public.roles;
create trigger trg_protect_last_editor
  before update or delete on public.roles
  for each row execute function public.protect_last_editor();
