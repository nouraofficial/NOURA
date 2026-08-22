-- ============================================================
-- NOURA 1.10 — HELP & SUPPORT + APP NOTIFICATIONS
-- Additive migration for the existing Noura database.
-- Admin account: Ogunbiyijesutomisin@gmail.com
-- Run after the existing Noura 1.10/community schema.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. ADMIN HELPER
-- ------------------------------------------------------------
create or replace function public.noura_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email','')) = lower('Ogunbiyijesutomisin@gmail.com');
$$;

revoke all on function public.noura_is_admin() from public;
grant execute on function public.noura_is_admin() to anon, authenticated;

-- ------------------------------------------------------------
-- 2. SUPPORT TICKETS
-- ------------------------------------------------------------
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  category text not null default 'other' check (category in ('bug','account','community','idea','vendor','order','other')),
  subject text not null default 'Noura Support Request',
  status text not null default 'open' check (status in ('open','in_progress','waiting_user','resolved','closed')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_support_tickets_user on public.support_tickets(user_id, created_at desc);
create index if not exists idx_support_tickets_status on public.support_tickets(status, created_at desc);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  sender_id uuid not null,
  sender_role text not null check (sender_role in ('user','admin')),
  body text not null check (length(trim(body)) > 0),
  attachment_url text,
  created_at timestamptz not null default now()
);

create index if not exists idx_support_messages_ticket on public.support_messages(ticket_id, created_at);

-- ------------------------------------------------------------
-- 3. NOTIFICATION PREFERENCES
-- ------------------------------------------------------------
create table if not exists public.notification_preferences (
  user_id uuid primary key,
  app_notifications boolean not null default true,
  social_notifications boolean not null default true,
  challenge_notifications boolean not null default true,
  vendor_notifications boolean not null default true,
  admin_announcements boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4. BROWSER/PWA PUSH SUBSCRIPTIONS
-- Stores subscriptions for future true background web-push delivery.
-- The current app also supports in-app notification polling.
-- ------------------------------------------------------------
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  endpoint text not null unique,
  p256dh text,
  auth text,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_push_subscriptions_user on public.push_subscriptions(user_id);

-- ------------------------------------------------------------
-- 5. RLS
-- ------------------------------------------------------------
alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.push_subscriptions enable row level security;

-- Tickets: user owns their own; Noura Admin sees everything.
drop policy if exists support_tickets_owner_select on public.support_tickets;
create policy support_tickets_owner_select on public.support_tickets
for select to authenticated
using (user_id = auth.uid() or public.noura_is_admin());

drop policy if exists support_tickets_owner_insert on public.support_tickets;
create policy support_tickets_owner_insert on public.support_tickets
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists support_tickets_owner_update on public.support_tickets;
create policy support_tickets_owner_update on public.support_tickets
for update to authenticated
using (user_id = auth.uid() or public.noura_is_admin())
with check (user_id = auth.uid() or public.noura_is_admin());

-- Messages: ticket owner and admin can read/write their side.
drop policy if exists support_messages_select on public.support_messages;
create policy support_messages_select on public.support_messages
for select to authenticated
using (
  public.noura_is_admin()
  or exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid())
);

drop policy if exists support_messages_insert on public.support_messages;
create policy support_messages_insert on public.support_messages
for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    public.noura_is_admin()
    or (sender_role = 'user' and exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = auth.uid()))
  )
);

-- Notification preferences.
drop policy if exists notification_preferences_owner on public.notification_preferences;
create policy notification_preferences_owner on public.notification_preferences
for all to authenticated
using (user_id = auth.uid() or public.noura_is_admin())
with check (user_id = auth.uid() or public.noura_is_admin());

-- Push subscriptions.
drop policy if exists push_subscriptions_owner on public.push_subscriptions;
create policy push_subscriptions_owner on public.push_subscriptions
for all to authenticated
using (user_id = auth.uid() or public.noura_is_admin())
with check (user_id = auth.uid() or public.noura_is_admin());

-- ------------------------------------------------------------
-- 6. NOTIFICATIONS TABLE SAFETY
-- Existing Noura table is reused; these policies only affect it
-- after RLS is enabled. Service-trigger inserts use SECURITY DEFINER.
-- ------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists notifications_owner_select on public.notifications;
create policy notifications_owner_select on public.notifications
for select to authenticated
using (user_id = auth.uid() or public.noura_is_admin());

drop policy if exists notifications_owner_update on public.notifications;
create policy notifications_owner_update on public.notifications
for update to authenticated
using (user_id = auth.uid() or public.noura_is_admin())
with check (user_id = auth.uid() or public.noura_is_admin());

drop policy if exists notifications_admin_insert on public.notifications;
create policy notifications_admin_insert on public.notifications
for insert to authenticated
with check (user_id = auth.uid() or public.noura_is_admin());

-- ------------------------------------------------------------
-- 7. NOTIFICATION HELPER
-- ------------------------------------------------------------
create or replace function public.noura_notify(
  p_user_id uuid,
  p_type text,
  p_icon text,
  p_color text,
  p_title text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then return; end if;
  insert into public.notifications(user_id,type,icon,color,title,message,unread,created_at)
  values(p_user_id,coalesce(p_type,'social'),coalesce(p_icon,'🔔'),coalesce(p_color,'#E8943A22'),left(coalesce(p_title,'Noura'),160),left(coalesce(p_message,''),1000),true,now());
exception when others then
  raise log 'noura_notify failed: %', sqlerrm;
end;
$$;

-- ------------------------------------------------------------
-- 8. SUPPORT -> ADMIN / USER NOTIFICATIONS
-- ------------------------------------------------------------
create or replace function public.noura_support_message_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ticket_user uuid;
begin
  select user_id into ticket_user from public.support_tickets where id = new.ticket_id;
  if new.sender_role = 'admin' then
    perform public.noura_notify(ticket_user,'support','🧡','#E8943A22','Noura Support replied','You have a new reply from the Noura Admin team.');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_support_message_notification on public.support_messages;
create trigger trg_support_message_notification
after insert on public.support_messages
for each row execute function public.noura_support_message_notify();

-- ------------------------------------------------------------
-- 9. FOLLOW -> NOTIFICATION
-- ------------------------------------------------------------
create or replace function public.noura_follow_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare n text;
begin
  begin
    select coalesce(name,'Someone') into n from public.profiles where id = new.follower_id;
  exception when others then n := 'Someone'; end;
  perform public.noura_notify(new.following_id,'social','👥','#E8943A22','New follower',coalesce(n,'Someone') || ' started following you on Noura.');
  return new;
end;
$$;

drop trigger if exists trg_follow_notification on public.community_follows;
create trigger trg_follow_notification after insert on public.community_follows for each row execute function public.noura_follow_notify();

-- ------------------------------------------------------------
-- 10. COMMENT -> NOTIFICATION
-- ------------------------------------------------------------
create or replace function public.noura_comment_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare post_owner uuid; n text;
begin
  select author_id into post_owner from public.community_posts where id = new.post_id;
  if post_owner is null or post_owner = new.user_id then return new; end if;
  n := coalesce(new.author_name,'Someone');
  perform public.noura_notify(post_owner,'social','💬','#E8943A22','New comment on your post',n || ' commented on your Noura post.');
  return new;
end;
$$;

drop trigger if exists trg_comment_notification on public.community_post_comments;
create trigger trg_comment_notification after insert on public.community_post_comments for each row execute function public.noura_comment_notify();

-- ------------------------------------------------------------
-- 11. NEW POST -> FOLLOWERS
-- Only followers are notified; this avoids a massive fan-out to
-- every campus user when Noura scales.
-- ------------------------------------------------------------
create or replace function public.noura_post_notify_followers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare author_name text; r record;
begin
  select coalesce(name,'Someone') into author_name from public.profiles where id = new.author_id;
  for r in select follower_id from public.community_follows where following_id = new.author_id loop
    perform public.noura_notify(r.follower_id,'social','🍳','#E8943A22','New post from ' || coalesce(author_name,'someone'),left(coalesce(new.body,new.recipe_title,'Something new was shared on Noura.'),180));
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_post_notification on public.community_posts;
create trigger trg_post_notification after insert on public.community_posts for each row when (new.status = 'published') execute function public.noura_post_notify_followers();

-- ------------------------------------------------------------
-- 12. SUPPORT UPDATED_AT
-- ------------------------------------------------------------
create or replace function public.noura_touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;

drop trigger if exists trg_support_ticket_updated_at on public.support_tickets;
create trigger trg_support_ticket_updated_at before update on public.support_tickets for each row execute function public.noura_touch_updated_at();

-- ------------------------------------------------------------
-- 13. SEED ADMIN ANNOUNCEMENT PREFERENCE ROW IS NOT NEEDED.
-- Existing users receive notifications automatically when triggers fire.
-- ------------------------------------------------------------

-- Verification
select table_name from information_schema.tables
where table_schema='public' and table_name in ('support_tickets','support_messages','notification_preferences','push_subscriptions')
order by table_name;

select tablename, rowsecurity from pg_tables
where schemaname='public' and tablename in ('support_tickets','support_messages','notification_preferences','push_subscriptions','notifications')
order by tablename;
