-- Sonder database schema.
--
-- Run this in the Supabase SQL editor (or apply supabase/migrations with the Supabase CLI).
-- It is idempotent: safe to run on a brand-new project and safe to re-run. It also upgrades a
-- database created from the earlier Sonder schema.
--
-- Access model: Sonder is a social app. Any signed-in user can read profiles, rated cities,
-- travel profiles, the feed and the follow graph; people can only create, change or delete their
-- own rows. Photo pins are private to their owner. Anonymous (signed-out) clients get nothing.

-- ---------------------------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------------------------

-- Keeps updated_at current on every UPDATE. Trigger functions can't be called through the
-- Data API, so living in the public schema exposes nothing.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- profiles: one row per user, created automatically at sign-up
-- ---------------------------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Traveller',
  first_name text not null default '',
  last_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Upgrades from the first version of the schema.
alter table public.profiles add column if not exists first_name text not null default '';
alter table public.profiles add column if not exists last_name text not null default '';
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_name_length') then
    -- "not valid" enforces the rule for new writes without failing on legacy rows.
    alter table public.profiles add constraint profiles_name_length check (
      char_length(display_name) between 1 and 120
      and char_length(first_name) <= 60
      and char_length(last_name) <= 60
    ) not valid;
  end if;
end $$;

-- Newest-first lists use created_at. People search is a substring match (ilike '%name%'),
-- which a b-tree can't serve; add a pg_trgm GIN index on display_name once there are enough
-- users for a sequential scan to matter.
create index if not exists profiles_created_at_idx on public.profiles (created_at desc);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- rated_cities: one row per user per city, with the ranked places stored as JSON
-- ---------------------------------------------------------------------------------------------

create table if not exists public.rated_cities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  city_name text not null,
  country text not null default '',
  flag text not null default '',
  photo_url text not null default '',
  latitude double precision,
  longitude double precision,
  cumulative_score double precision not null,
  summary text not null default '',
  highlight text not null default '',
  would_recommend_if text not null default '',
  score_breakdown jsonb,
  top_attraction_name text,
  -- [{ "attraction_id", "name", "category", "sentiment", "rank" }]
  ratings jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, city_name, country)
);

alter table public.rated_cities add column if not exists latitude double precision;
alter table public.rated_cities add column if not exists longitude double precision;
alter table public.rated_cities add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rated_cities_valid') then
    alter table public.rated_cities add constraint rated_cities_valid check (
      cumulative_score between 0 and 10
      and char_length(city_name) between 1 and 120
      and char_length(country) <= 120
      and jsonb_typeof(ratings) = 'array'
      and (latitude is null or latitude between -90 and 90)
      and (longitude is null or longitude between -180 and 180)
    ) not valid;
  end if;
end $$;

-- The unique constraint already indexes (user_id, ...) for "my cities" lookups.

drop trigger if exists rated_cities_set_updated_at on public.rated_cities;
create trigger rated_cities_set_updated_at
  before update on public.rated_cities
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- travel_profiles: the inferred travel personality, one row per user
-- ---------------------------------------------------------------------------------------------

create table if not exists public.travel_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  personality_type text not null default '',
  personality_description text not null default '',
  taste_traits jsonb not null default '[]'::jsonb,
  -- [{ "destination", "match_reason", "vibe_tags", "match_score" }]
  recommendations jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

drop trigger if exists travel_profiles_set_updated_at on public.travel_profiles;
create trigger travel_profiles_set_updated_at
  before update on public.travel_profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- city_attractions: places travellers have added for a city, shown to others as suggestions
-- ---------------------------------------------------------------------------------------------

create table if not exists public.city_attractions (
  id uuid primary key default gen_random_uuid(),
  city_name text not null,
  country text not null default '',
  name text not null,
  category text not null,
  added_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'city_attractions_unique_place') then
    -- Older databases may hold exact duplicates; keep the earliest copy of each.
    delete from public.city_attractions a
    using public.city_attractions b
    where a.city_name = b.city_name
      and a.country = b.country
      and a.name = b.name
      and (a.created_at, a.id) > (b.created_at, b.id);

    alter table public.city_attractions
      add constraint city_attractions_unique_place unique (city_name, country, name);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'city_attractions_valid') then
    alter table public.city_attractions add constraint city_attractions_valid check (
      char_length(name) between 1 and 120
      and char_length(city_name) between 1 and 120
      and category in (
        'Museums & Culture',
        'Parks & Nature',
        'Food & Markets',
        'Neighbourhoods & Walks',
        'Experiences & Activities',
        'Viewpoints & Landmarks'
      )
    ) not valid;
  end if;
end $$;

-- Superseded by the unique constraint, which indexes (city_name, country, name).
drop index if exists public.idx_city_attractions_city_country;
create index if not exists city_attractions_added_by_idx on public.city_attractions (added_by);

-- ---------------------------------------------------------------------------------------------
-- feed_activities: the social feed
-- ---------------------------------------------------------------------------------------------

create table if not exists public.feed_activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rated_city_id uuid references public.rated_cities (id) on update cascade on delete cascade,
  display_name text not null default 'Traveller',
  -- 'visited_city' | 'rated_attraction' | 'added_favourite'
  activity_type text not null,
  city text not null,
  country text not null default '',
  city_photo_url text,
  score double precision,
  review text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Deleting a city also removes the post that announced it.
alter table public.feed_activities
  add column if not exists rated_city_id uuid references public.rated_cities (id) on update cascade on delete cascade;

create index if not exists feed_activities_created_at_idx on public.feed_activities (created_at desc);
create index if not exists feed_activities_user_created_idx on public.feed_activities (user_id, created_at desc);
create index if not exists feed_activities_rated_city_idx on public.feed_activities (rated_city_id);

-- ---------------------------------------------------------------------------------------------
-- follows: who follows whom
-- ---------------------------------------------------------------------------------------------

create table if not exists public.follows (
  follower_id uuid not null references auth.users (id) on delete cascade,
  following_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_not_self check (follower_id <> following_id)
);

-- The primary key covers "who do I follow"; this covers "who follows me".
create index if not exists follows_following_idx on public.follows (following_id, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- photo_pins: location-tagged travel photos shown on the owner's map
-- ---------------------------------------------------------------------------------------------

create table if not exists public.photo_pins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  photo_url text not null,
  storage_path text,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location_name text,
  caption text check (caption is null or char_length(caption) <= 500),
  taken_at timestamptz,
  uploaded_at timestamptz not null default now()
);

create index if not exists photo_pins_user_uploaded_idx on public.photo_pins (user_id, uploaded_at desc);

-- ---------------------------------------------------------------------------------------------
-- Privileges: signed-in users only, and only the operations the app performs.
-- Row-level security (below) then decides which rows.
-- ---------------------------------------------------------------------------------------------

revoke all on table
  public.profiles,
  public.rated_cities,
  public.travel_profiles,
  public.city_attractions,
  public.feed_activities,
  public.follows,
  public.photo_pins
from anon, authenticated;

grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.rated_cities to authenticated;
grant select, insert, update on table public.travel_profiles to authenticated;
grant select, insert on table public.city_attractions to authenticated;
grant select, insert, update, delete on table public.feed_activities to authenticated;
grant select, insert, delete on table public.follows to authenticated;
grant select, insert, delete on table public.photo_pins to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Row-level security
-- (auth.uid() is wrapped in a subquery so it is evaluated once per statement, not per row.)
-- ---------------------------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.rated_cities enable row level security;
alter table public.travel_profiles enable row level security;
alter table public.city_attractions enable row level security;
alter table public.feed_activities enable row level security;
alter table public.follows enable row level security;
alter table public.photo_pins enable row level security;

-- Remove policies from the earlier schema (they were open to signed-out clients or own-row only).
drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can read own rated_cities" on public.rated_cities;
drop policy if exists "Users can insert own rated_cities" on public.rated_cities;
drop policy if exists "Users can delete own rated_cities" on public.rated_cities;
drop policy if exists "Users can read own travel_profiles" on public.travel_profiles;
drop policy if exists "Users can insert own travel_profiles" on public.travel_profiles;
drop policy if exists "Users can update own travel_profiles" on public.travel_profiles;
drop policy if exists "Anyone can read city_attractions" on public.city_attractions;
drop policy if exists "Authenticated users can insert city_attractions" on public.city_attractions;
drop policy if exists "Anyone can read feed_activities" on public.feed_activities;
drop policy if exists "Users can insert own feed_activities" on public.feed_activities;

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- rated_cities
drop policy if exists rated_cities_select on public.rated_cities;
create policy rated_cities_select on public.rated_cities
  for select to authenticated using (true);

drop policy if exists rated_cities_insert_own on public.rated_cities;
create policy rated_cities_insert_own on public.rated_cities
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists rated_cities_update_own on public.rated_cities;
create policy rated_cities_update_own on public.rated_cities
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists rated_cities_delete_own on public.rated_cities;
create policy rated_cities_delete_own on public.rated_cities
  for delete to authenticated using ((select auth.uid()) = user_id);

-- travel_profiles
drop policy if exists travel_profiles_select on public.travel_profiles;
create policy travel_profiles_select on public.travel_profiles
  for select to authenticated using (true);

drop policy if exists travel_profiles_insert_own on public.travel_profiles;
create policy travel_profiles_insert_own on public.travel_profiles
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists travel_profiles_update_own on public.travel_profiles;
create policy travel_profiles_update_own on public.travel_profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- city_attractions (append-only for clients)
drop policy if exists city_attractions_select on public.city_attractions;
create policy city_attractions_select on public.city_attractions
  for select to authenticated using (true);

drop policy if exists city_attractions_insert_own on public.city_attractions;
create policy city_attractions_insert_own on public.city_attractions
  for insert to authenticated with check ((select auth.uid()) = added_by);

-- feed_activities
drop policy if exists feed_activities_select on public.feed_activities;
create policy feed_activities_select on public.feed_activities
  for select to authenticated using (true);

drop policy if exists feed_activities_insert_own on public.feed_activities;
create policy feed_activities_insert_own on public.feed_activities
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists feed_activities_update_own on public.feed_activities;
create policy feed_activities_update_own on public.feed_activities
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists feed_activities_delete_own on public.feed_activities;
create policy feed_activities_delete_own on public.feed_activities
  for delete to authenticated using ((select auth.uid()) = user_id);

-- follows
drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows
  for select to authenticated using (true);

drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own on public.follows
  for insert to authenticated with check ((select auth.uid()) = follower_id);

drop policy if exists follows_delete_own on public.follows;
create policy follows_delete_own on public.follows
  for delete to authenticated using ((select auth.uid()) = follower_id);

-- photo_pins (private to the owner)
drop policy if exists photo_pins_select_own on public.photo_pins;
create policy photo_pins_select_own on public.photo_pins
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists photo_pins_insert_own on public.photo_pins;
create policy photo_pins_insert_own on public.photo_pins
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists photo_pins_delete_own on public.photo_pins;
create policy photo_pins_delete_own on public.photo_pins
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------------------------
-- Sign-up: create the profile row from the names captured in the sign-up form
-- ---------------------------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first text := left(trim(coalesce(new.raw_user_meta_data ->> 'first_name', '')), 60);
  v_last text := left(trim(coalesce(new.raw_user_meta_data ->> 'last_name', '')), 60);
  v_display text;
begin
  v_display := trim(v_first || ' ' || v_last);
  if v_display = '' then
    v_display := left(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 120);
  end if;
  if v_display = '' then
    v_display := 'Traveller';
  end if;

  insert into public.profiles (id, display_name, first_name, last_name)
  values (new.id, v_display, v_first, v_last)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- The function is only ever run by the trigger. Remove the default PUBLIC execute grant so it is
-- not exposed as an RPC; the auth service role keeps execute for the trigger itself.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.handle_new_user() to supabase_auth_admin;
  end if;
end $$;

-- Accounts created before the trigger existed (or while it was failing) get a profile now.
insert into public.profiles (id, display_name, first_name, last_name)
select
  u.id,
  coalesce(
    nullif(trim(
      left(trim(coalesce(u.raw_user_meta_data ->> 'first_name', '')), 60) || ' ' ||
      left(trim(coalesce(u.raw_user_meta_data ->> 'last_name', '')), 60)
    ), ''),
    nullif(left(trim(coalesce(u.raw_user_meta_data ->> 'display_name', '')), 120), ''),
    'Traveller'
  ),
  left(trim(coalesce(u.raw_user_meta_data ->> 'first_name', '')), 60),
  left(trim(coalesce(u.raw_user_meta_data ->> 'last_name', '')), 60)
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Account deletion (called by the app as an RPC; App Store guideline 5.1.1(v))
-- ---------------------------------------------------------------------------------------------

-- Deletes the calling user. Every table above cascades from auth.users.
create or replace function public.delete_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := (select auth.uid());
begin
  if v_caller is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  delete from auth.users where id = v_caller;
end;
$$;

revoke execute on function public.delete_user() from public, anon;
grant execute on function public.delete_user() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Storage: travel photos
-- ---------------------------------------------------------------------------------------------

-- Public bucket: photos are served by unguessable URL; only JPEGs up to 5 MB are accepted.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 5242880, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- People can only write, list and delete inside their own folder: photos/<user id>/<file>.jpg
drop policy if exists sonder_photos_insert_own on storage.objects;
create policy sonder_photos_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists sonder_photos_select_own on storage.objects;
create policy sonder_photos_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists sonder_photos_delete_own on storage.objects;
create policy sonder_photos_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
