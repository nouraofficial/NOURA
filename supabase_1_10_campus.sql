
-- NOURA 1.10 CAMPUS FOOD FOUNDATION
-- Run once in Supabase SQL Editor before deploying the matching frontend.
-- Safe to re-run: columns/indexes/policies are guarded.

begin;

-- 1) Location + image fields used by the new vendor radar/storefront.
alter table if exists public.restaurants add column if not exists latitude double precision;
alter table if exists public.restaurants add column if not exists longitude double precision;
alter table if exists public.menu_items add column if not exists image_url text;
alter table if exists public.vendors add column if not exists latitude double precision;
alter table if exists public.vendors add column if not exists longitude double precision;

create index if not exists restaurants_lat_lng_idx on public.restaurants(latitude, longitude);
create unique index if not exists restaurants_slug_unique_idx on public.restaurants(slug) where slug is not null;

-- 2) Prevent accidental duplicate vendor/store records for one vendor.
create unique index if not exists restaurants_vendor_id_unique_idx on public.restaurants(vendor_id) where vendor_id is not null;

-- 3) Storage bucket for real vendor/menu photos.
insert into storage.buckets (id, name, public)
values ('vendor-photos','vendor-photos',true)
on conflict (id) do update set public = true;

-- 4) RLS: profiles must be readable/writable only by the signed-in owner.
alter table if exists public.profiles enable row level security;
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid());
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- 5) User settings/preferences are also owner-only.
alter table if exists public.user_settings enable row level security;
drop policy if exists user_settings_own_select on public.user_settings;
drop policy if exists user_settings_own_insert on public.user_settings;
drop policy if exists user_settings_own_update on public.user_settings;
create policy user_settings_own_select on public.user_settings for select to authenticated using (user_id = auth.uid());
create policy user_settings_own_insert on public.user_settings for insert to authenticated with check (user_id = auth.uid());
create policy user_settings_own_update on public.user_settings for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table if exists public.user_preferences enable row level security;
drop policy if exists user_preferences_own_select on public.user_preferences;
drop policy if exists user_preferences_own_insert on public.user_preferences;
drop policy if exists user_preferences_own_update on public.user_preferences;
create policy user_preferences_own_select on public.user_preferences for select to authenticated using (user_id = auth.uid());
create policy user_preferences_own_insert on public.user_preferences for insert to authenticated with check (user_id = auth.uid());
create policy user_preferences_own_update on public.user_preferences for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 6) Public discovery: anyone may read published restaurant/menu data.
alter table if exists public.restaurants enable row level security;
drop policy if exists restaurants_public_read on public.restaurants;
create policy restaurants_public_read on public.restaurants for select to anon, authenticated using (true);

alter table if exists public.menu_items enable row level security;
drop policy if exists menu_items_public_read on public.menu_items;
create policy menu_items_public_read on public.menu_items for select to anon, authenticated using (true);

-- 7) Vendor ownership policies. Vendors are linked to auth_user_id.
alter table if exists public.vendors enable row level security;
drop policy if exists vendors_own_select on public.vendors;
drop policy if exists vendors_own_insert on public.vendors;
drop policy if exists vendors_own_update on public.vendors;
create policy vendors_own_select on public.vendors for select to authenticated using (auth_user_id = auth.uid());
create policy vendors_own_insert on public.vendors for insert to authenticated with check (auth_user_id = auth.uid());
create policy vendors_own_update on public.vendors for update to authenticated using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());

-- Vendor-owned restaurants/menu writes; public reads remain available.
drop policy if exists restaurants_vendor_write on public.restaurants;
create policy restaurants_vendor_write on public.restaurants for all to authenticated
using (exists (select 1 from public.vendors v where v.id = restaurants.vendor_id and v.auth_user_id = auth.uid()))
with check (exists (select 1 from public.vendors v where v.id = restaurants.vendor_id and v.auth_user_id = auth.uid()));

drop policy if exists menu_items_vendor_write on public.menu_items;
create policy menu_items_vendor_write on public.menu_items for all to authenticated
using (exists (select 1 from public.restaurants r join public.vendors v on v.id = r.vendor_id where r.id = menu_items.restaurant_id and v.auth_user_id = auth.uid()))
with check (exists (select 1 from public.restaurants r join public.vendors v on v.id = r.vendor_id where r.id = menu_items.restaurant_id and v.auth_user_id = auth.uid()));

-- 8) Storage: public can read images; authenticated vendors can write under their user folder.
drop policy if exists vendor_photos_public_read on storage.objects;
create policy vendor_photos_public_read on storage.objects for select to public using (bucket_id='vendor-photos');
drop policy if exists vendor_photos_owner_insert on storage.objects;
create policy vendor_photos_owner_insert on storage.objects for insert to authenticated with check (bucket_id='vendor-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists vendor_photos_owner_update on storage.objects;
create policy vendor_photos_owner_update on storage.objects for update to authenticated using (bucket_id='vendor-photos' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id='vendor-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 9) Critical advisor warning: public.users is not needed by the current frontend.
-- Keep it protected. Do not add a broad public policy.
alter table if exists public.users enable row level security;

commit;

-- ============================================================
-- NOURA 1.10 — CAMPUS EXPERIENCE LAYER
-- Additive extension for Home / Discover / Plan / Vendor.
-- Safe to re-run.
-- ============================================================

create table if not exists public.campuses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text,
  slug text not null unique,
  city text,
  state text,
  country text default 'Nigeria',
  latitude double precision,
  longitude double precision,
  radius_meters integer default 5000,
  logo_url text,
  cover_image_url text,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.campus_food_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  icon text,
  description text,
  sort_order integer default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table if exists public.users add column if not exists campus_id uuid references public.campuses(id) on delete set null;
alter table if exists public.users add column if not exists campus_role text check (campus_role in ('student','staff','visitor','local'));
alter table if exists public.users add column if not exists food_mode text check (food_mode in ('cook','buy','order','mixed'));
alter table if exists public.users add column if not exists onboarding_completed boolean default false;

alter table if exists public.vendors add column if not exists campus_id uuid references public.campuses(id) on delete set null;
alter table if exists public.vendors add column if not exists campus_verified boolean default false;
alter table if exists public.vendors add column if not exists student_favourite boolean default false;
alter table if exists public.vendors add column if not exists cover_image_url text;
alter table if exists public.vendors add column if not exists logo_url text;

alter table if exists public.restaurants add column if not exists campus_id uuid references public.campuses(id) on delete set null;
alter table if exists public.restaurants add column if not exists student_favourite boolean default false;
alter table if exists public.restaurants add column if not exists cover_image_url text;
alter table if exists public.restaurants add column if not exists logo_url text;

alter table if exists public.menu_items add column if not exists category_id uuid references public.campus_food_categories(id) on delete set null;
alter table if exists public.menu_items add column if not exists is_available boolean default true;
alter table if exists public.menu_items add column if not exists preparation_minutes integer;
alter table if exists public.menu_items add column if not exists student_favourite boolean default false;
alter table if exists public.menu_items add column if not exists campus_special boolean default false;

create table if not exists public.food_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  campus_id uuid references public.campuses(id) on delete set null,
  period_type text not null check (period_type in ('daily','weekly','monthly')),
  budget_amount numeric(12,2) not null check (budget_amount >= 0),
  spent_amount numeric(12,2) default 0 check (spent_amount >= 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.food_budget_entries (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.food_budgets(id) on delete cascade,
  user_id uuid not null,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  vendor_id uuid references public.vendors(id) on delete set null,
  amount numeric(12,2) not null check (amount >= 0),
  note text,
  created_at timestamptz default now()
);

create table if not exists public.campus_deals (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid references public.campuses(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  title text not null,
  description text,
  original_price numeric(12,2),
  deal_price numeric(12,2),
  image_url text,
  starts_at timestamptz default now(),
  ends_at timestamptz,
  is_active boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.food_saves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  vendor_id uuid references public.vendors(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete cascade,
  created_at timestamptz default now(),
  check (vendor_id is not null or menu_item_id is not null)
);

create table if not exists public.food_discovery_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  campus_id uuid references public.campuses(id) on delete set null,
  vendor_id uuid references public.vendors(id) on delete set null,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  event_type text not null check (event_type in ('view_vendor','view_menu_item','save_vendor','save_menu_item','search','direction','contact','share')),
  search_query text,
  created_at timestamptz default now()
);

create table if not exists public.quick_food_options (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid references public.vendors(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete cascade,
  campus_id uuid references public.campuses(id) on delete cascade,
  max_minutes integer not null check (max_minutes > 0),
  is_active boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.campus_food_trends (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  score numeric(12,4) default 0,
  views integer default 0,
  saves integer default 0,
  contacts integer default 0,
  trend_date date not null default current_date,
  created_at timestamptz default now(),
  unique(campus_id, menu_item_id, trend_date)
);

alter table if exists public.challenges add column if not exists campus_id uuid references public.campuses(id) on delete cascade;
alter table if exists public.challenges add column if not exists student_only boolean default false;

create index if not exists users_campus_idx on public.users(campus_id);
create index if not exists vendors_campus_idx on public.vendors(campus_id);
create index if not exists vendors_location_idx on public.vendors(latitude, longitude);
create index if not exists restaurants_campus_idx on public.restaurants(campus_id);
create index if not exists restaurants_location_idx on public.restaurants(latitude, longitude);
create index if not exists menu_items_campus_category_idx on public.menu_items(category_id);
create index if not exists campus_deals_campus_idx on public.campus_deals(campus_id);
create index if not exists discovery_campus_created_idx on public.food_discovery_events(campus_id, created_at);
create index if not exists trends_campus_date_idx on public.campus_food_trends(campus_id, trend_date);

create unique index if not exists food_saves_vendor_unique_idx on public.food_saves(user_id, vendor_id) where vendor_id is not null;
create unique index if not exists food_saves_menu_unique_idx on public.food_saves(user_id, menu_item_id) where menu_item_id is not null;

insert into public.campus_food_categories(name,slug,icon,description,sort_order) values
('Proper Meals','proper-meals','🍛','Rice, pasta, swallow and full meals',1),
('Quick Bites','quick-bites','🥪','Fast food for students between classes',2),
('Snacks','snacks','🍪','Small bites and affordable snacks',3),
('Drinks','drinks','🥤','Drinks and refreshments',4),
('Breakfast','breakfast','🍳','Breakfast options for early mornings',5),
('Bakery','bakery','🧁','Cakes, bread and baked goods',6),
('Budget Meals','budget-meals','💰','Affordable student-friendly meals',7),
('Healthy','healthy','🥗','Health-conscious food options',8)
on conflict(slug) do nothing;

-- New campus-owned tables are protected immediately.
alter table public.campuses enable row level security;
alter table public.campus_food_categories enable row level security;
alter table public.food_budgets enable row level security;
alter table public.food_budget_entries enable row level security;
alter table public.campus_deals enable row level security;
alter table public.food_saves enable row level security;
alter table public.food_discovery_events enable row level security;
alter table public.quick_food_options enable row level security;
alter table public.campus_food_trends enable row level security;

drop policy if exists campuses_public_read on public.campuses;
create policy campuses_public_read on public.campuses for select to anon, authenticated using (is_active = true);

drop policy if exists campus_categories_public_read on public.campus_food_categories;
create policy campus_categories_public_read on public.campus_food_categories for select to anon, authenticated using (is_active = true);

drop policy if exists campus_deals_public_read on public.campus_deals;
create policy campus_deals_public_read on public.campus_deals for select to anon, authenticated using (is_active = true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now()));

drop policy if exists quick_food_public_read on public.quick_food_options;
create policy quick_food_public_read on public.quick_food_options for select to anon, authenticated using (is_active = true);

drop policy if exists campus_trends_public_read on public.campus_food_trends;
create policy campus_trends_public_read on public.campus_food_trends for select to anon, authenticated using (true);

drop policy if exists food_budgets_owner on public.food_budgets;
create policy food_budgets_owner on public.food_budgets for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists food_budget_entries_owner on public.food_budget_entries;
create policy food_budget_entries_owner on public.food_budget_entries for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists food_saves_owner on public.food_saves;
create policy food_saves_owner on public.food_saves for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists food_events_insert on public.food_discovery_events;
create policy food_events_insert on public.food_discovery_events for insert to authenticated with check (user_id = auth.uid());

drop policy if exists food_events_owner_read on public.food_discovery_events;
create policy food_events_owner_read on public.food_discovery_events for select to authenticated using (user_id = auth.uid());

-- Example campus seed (safe to re-run). Uncomment and adjust coordinates if needed.
-- insert into public.campuses(name,short_name,slug,city,state,country,latitude,longitude)
-- values('Obafemi Awolowo University','OAU','oau','Ile-Ife','Osun','Nigeria',7.517,4.527)
-- on conflict(slug) do nothing;

alter table if exists public.user_preferences add column if not exists campus_id uuid references public.campuses(id) on delete set null;
alter table if exists public.user_preferences add column if not exists daily_food_budget numeric(12,2);
alter table if exists public.user_preferences add column if not exists weekly_food_budget numeric(12,2);
alter table if exists public.user_preferences add column if not exists preferred_mode text check (preferred_mode in ('cook','buy','order','mixed'));
alter table if exists public.user_preferences add column if not exists cooking_frequency text check (cooking_frequency in ('never','rarely','sometimes','often','always'));

-- ============================================================
-- NOURA 1.10 — CAMPUS COMMUNITY LAYER
-- Additive. Safe to re-run.
-- ============================================================

-- Community photo storage. Public read; authenticated users may only
-- write/delete files inside their own auth uid folder.
insert into storage.buckets (id, name, public)
values ('community-media','community-media',true)
on conflict (id) do update set public = true;

drop policy if exists community_media_public_read on storage.objects;
create policy community_media_public_read
on storage.objects for select to anon, authenticated
using (bucket_id = 'community-media');

drop policy if exists community_media_owner_insert on storage.objects;
create policy community_media_owner_insert
on storage.objects for insert to authenticated
with check (bucket_id = 'community-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists community_media_owner_update on storage.objects;
create policy community_media_owner_update
on storage.objects for update to authenticated
using (bucket_id = 'community-media' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'community-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists community_media_owner_delete on storage.objects;
create policy community_media_owner_delete
on storage.objects for delete to authenticated
using (bucket_id = 'community-media' and (storage.foldername(name))[1] = auth.uid()::text);

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null,
  author_name text not null default 'Noura user',
  author_username text not null default '@user',
  author_avatar_url text,
  post_type text not null default 'post' check (post_type in ('post','recipe','vendor','challenge')),
  body text,
  image_url text,
  recipe_source text,
  recipe_id text,
  recipe_title text,
  recipe_image_url text,
  recipe_area text,
  recipe_category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_posts_has_content check (
    nullif(trim(coalesce(body,'')),'') is not null
    or nullif(trim(coalesce(image_url,'')),'') is not null
    or nullif(trim(coalesce(recipe_title,'')),'') is not null
  )
);

create table if not exists public.community_post_likes (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);

create table if not exists public.community_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  user_id uuid not null,
  author_name text not null default 'Noura user',
  author_username text not null default '@user',
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.community_follows (
  follower_id uuid not null,
  following_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (follower_id,following_id),
  check (follower_id <> following_id)
);

create table if not exists public.community_challenge_participants (
  challenge_id text not null,
  user_id uuid not null,
  joined_at timestamptz not null default now(),
  primary key (challenge_id,user_id)
);

create index if not exists community_posts_created_idx on public.community_posts(created_at desc);
create index if not exists community_posts_author_idx on public.community_posts(author_id,created_at desc);
create index if not exists community_posts_recipe_idx on public.community_posts(post_type,recipe_source,recipe_id);
create index if not exists community_comments_post_idx on public.community_post_comments(post_id,created_at);
create index if not exists community_follows_following_idx on public.community_follows(following_id);
create index if not exists community_challenge_idx on public.community_challenge_participants(challenge_id,joined_at);

alter table public.community_posts enable row level security;
alter table public.community_post_likes enable row level security;
alter table public.community_post_comments enable row level security;
alter table public.community_follows enable row level security;
alter table public.community_challenge_participants enable row level security;

drop policy if exists community_posts_public_read on public.community_posts;
create policy community_posts_public_read on public.community_posts
for select to anon, authenticated using (true);

drop policy if exists community_posts_owner_insert on public.community_posts;
create policy community_posts_owner_insert on public.community_posts
for insert to authenticated
with check (author_id = auth.uid());

drop policy if exists community_posts_owner_update on public.community_posts;
create policy community_posts_owner_update on public.community_posts
for update to authenticated
using (author_id = auth.uid()) with check (author_id = auth.uid());

drop policy if exists community_posts_owner_delete on public.community_posts;
create policy community_posts_owner_delete on public.community_posts
for delete to authenticated using (author_id = auth.uid());

drop policy if exists community_likes_owner_select on public.community_post_likes;
create policy community_likes_owner_select on public.community_post_likes
for select to authenticated using (user_id = auth.uid());

drop policy if exists community_likes_owner_insert on public.community_post_likes;
create policy community_likes_owner_insert on public.community_post_likes
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists community_likes_owner_delete on public.community_post_likes;
create policy community_likes_owner_delete on public.community_post_likes
for delete to authenticated using (user_id = auth.uid());

drop policy if exists community_comments_public_read on public.community_post_comments;
create policy community_comments_public_read on public.community_post_comments
for select to anon, authenticated using (true);

drop policy if exists community_comments_owner_insert on public.community_post_comments;
create policy community_comments_owner_insert on public.community_post_comments
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists community_comments_owner_update on public.community_post_comments;
create policy community_comments_owner_update on public.community_post_comments
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists community_comments_owner_delete on public.community_post_comments;
create policy community_comments_owner_delete on public.community_post_comments
for delete to authenticated using (user_id = auth.uid());

drop policy if exists community_follows_owner_select on public.community_follows;
create policy community_follows_owner_select on public.community_follows
for select to authenticated using (follower_id = auth.uid());

drop policy if exists community_follows_owner_insert on public.community_follows;
create policy community_follows_owner_insert on public.community_follows
for insert to authenticated with check (follower_id = auth.uid());

drop policy if exists community_follows_owner_delete on public.community_follows;
create policy community_follows_owner_delete on public.community_follows
for delete to authenticated using (follower_id = auth.uid());

drop policy if exists community_challenges_public_read on public.community_challenge_participants;
create policy community_challenges_public_read on public.community_challenge_participants
for select to anon, authenticated using (true);

drop policy if exists community_challenges_owner_insert on public.community_challenge_participants;
create policy community_challenges_owner_insert on public.community_challenge_participants
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists community_challenges_owner_delete on public.community_challenge_participants;
create policy community_challenges_owner_delete on public.community_challenge_participants
for delete to authenticated using (user_id = auth.uid());

-- Helpful public-safe counts. These do not expose private post authors or user data.
create or replace view public.community_post_stats as
select
  p.id as post_id,
  count(distinct l.user_id)::integer as likes_count,
  count(distinct c.id)::integer as comments_count
from public.community_posts p
left join public.community_post_likes l on l.post_id = p.id
left join public.community_post_comments c on c.post_id = p.id
group by p.id;

grant select on public.community_post_stats to anon, authenticated;

commit;
