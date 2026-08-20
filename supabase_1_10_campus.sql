
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
