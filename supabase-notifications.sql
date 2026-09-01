-- SPHUB Tracker — team members + assignment email notifications
-- Run after supabase-setup.sql. Safe to re-run.

-- Team directory: powers the assignee dropdown and email routing.
create table if not exists public.members (
  email text primary key,
  name text not null,
  notify_frequency text not null default 'instant', -- instant | hourly | daily | off
  last_notified_at timestamptz
);
alter table public.members enable row level security;
drop policy if exists "authenticated all" on public.members;
create policy "authenticated all" on public.members
  for all to authenticated using (true) with check (true);

-- Queue of pending assignment emails, filled by trigger, drained by cron.
create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  member_email text not null,
  issue_id text not null,
  issue_title text not null default '',
  kind text not null default 'assigned',
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.notifications enable row level security;
-- no client policies: only the trigger/cron (definer functions) touch it

-- Secrets the email sender needs (no client policies = clients can never read them).
create table if not exists public.app_secrets (
  name text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;

-- Queue an email whenever an issue's assignee changes to someone.
create or replace function public.queue_assignment_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_email text := new.data->>'assigneeEmail';
  old_email text := case when tg_op = 'UPDATE' then old.data->>'assigneeEmail' else null end;
begin
  if new_email is not null and new_email <> '' and new_email is distinct from old_email then
    insert into notifications (member_email, issue_id, issue_title, kind)
    values (new_email, new.id, coalesce(new.data->>'title', ''), 'assigned');
  end if;
  return new;
end $$;

drop trigger if exists trg_issue_assign on public.issues;
create trigger trg_issue_assign
  after insert or update on public.issues
  for each row execute function public.queue_assignment_notification();

-- Drain the queue per member, honoring each member's frequency.
create or replace function public.send_pending_notifications()
returns void language plpgsql security definer set search_path = public as $$
declare
  api_key text;
  from_addr text;
  m record;
  items text;
  cnt int;
begin
  select value into api_key from app_secrets where name = 'resend_api_key';
  if api_key is null then return; end if;
  select value into from_addr from app_secrets where name = 'notify_from';
  if from_addr is null then from_addr := 'SPHUB Tracker <onboarding@resend.dev>'; end if;

  for m in
    select mem.email, mem.name, mem.notify_frequency, mem.last_notified_at
    from members mem
    where exists (select 1 from notifications n where n.member_email = mem.email and n.sent_at is null)
  loop
    if m.notify_frequency = 'off' then
      update notifications set sent_at = now() where member_email = m.email and sent_at is null;
      continue;
    end if;
    if m.notify_frequency = 'hourly' and m.last_notified_at is not null
       and m.last_notified_at > now() - interval '1 hour' then continue; end if;
    if m.notify_frequency = 'daily' and m.last_notified_at is not null
       and m.last_notified_at > now() - interval '24 hours' then continue; end if;

    select string_agg('<li><b>' || issue_id || '</b> — ' || coalesce(nullif(issue_title, ''), '(untitled)') || '</li>', ''),
           count(*)
      into items, cnt
      from notifications
     where member_email = m.email and sent_at is null;

    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || api_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', from_addr,
        'to', jsonb_build_array(m.email),
        'subject', 'SPHUB Tracker: ' || cnt || ' task' || case when cnt > 1 then 's' else '' end || ' assigned to you',
        'html', '<p>Hi ' || m.name || ',</p><p>New SPHUB tasks were assigned to you:</p><ul>' || items ||
                '</ul><p><a href="https://fouseysp.github.io/SPHUB-issue-tracker/">Open the tracker</a></p>'
      )
    );

    update notifications set sent_at = now() where member_email = m.email and sent_at is null;
    update members set last_notified_at = now() where email = m.email;
  end loop;
end $$;

-- Run the sender every 5 minutes ("instant" = within ~5 min).
create extension if not exists pg_net;
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('sphub-notify');
exception when others then null;
end $$;
select cron.schedule('sphub-notify', '*/5 * * * *', 'select public.send_pending_notifications()');

-- To activate email delivery, set your Resend API key (run in SQL editor):
-- insert into app_secrets (name, value) values ('resend_api_key', 're_YOUR_KEY')
--   on conflict (name) do update set value = excluded.value;
-- Optional custom sender (needs a domain verified in Resend):
-- insert into app_secrets (name, value) values ('notify_from', 'SPHUB Tracker <tracker@saudipanther.sa>')
--   on conflict (name) do update set value = excluded.value;
