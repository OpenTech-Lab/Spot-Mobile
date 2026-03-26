create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.set_geography_from_coordinates()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.latitude is null or new.longitude is null then
    new.gps = null;
    return new;
  end if;

  new.gps = extensions.st_setsrid(
    extensions.st_makepoint(new.longitude, new.latitude),
    4326
  )::extensions.geography;

  return new;
end;
$$;

create or replace function public.set_event_location_from_coordinates()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.latitude is null or new.longitude is null then
    new.location = null;
    return new;
  end if;

  new.location = extensions.st_setsrid(
    extensions.st_makepoint(new.longitude, new.latitude),
    4326
  )::extensions.geography;

  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  legacy_pubkey text,
  legacy_npub text,
  device_id text,
  avatar_seed text,
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now())
);

create table if not exists public.events (
  id uuid primary key default extensions.gen_random_uuid(),
  hashtag text not null unique,
  title text,
  description text,
  creator_id uuid references public.profiles(id) on delete set null,
  latitude double precision,
  longitude double precision,
  location extensions.geography(Point, 4326),
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now())
);

create table if not exists public.posts (
  id uuid primary key default extensions.gen_random_uuid(),
  event_hashtag text references public.events(hashtag) on delete set null,
  event_tags text[] not null default '{}',
  user_id uuid not null references public.profiles(id) on delete cascade,
  content_hashes text[] not null default '{}',
  media_type text not null default 'text'
    check (media_type in ('image', 'video', 'text')),
  caption text,
  latitude double precision,
  longitude double precision,
  gps extensions.geography(Point, 4326),
  view_count integer not null default 0,
  reply_count integer not null default 0,
  like_count integer not null default 0,
  preview_base64 text,
  preview_mime_type text,
  source_type text not null default 'firsthand'
    check (source_type in ('firsthand', 'secondhand')),
  is_danger_mode boolean not null default false,
  is_virtual boolean not null default false,
  is_ai_generated boolean not null default false,
  is_text_only boolean not null default false,
  reply_to_id uuid references public.posts(id) on delete set null,
  spot_name text,
  tags text[] not null default '{}',
  deleted_at timestamp with time zone,
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now())
);

create table if not exists public.witness_signals (
  id uuid primary key default extensions.gen_random_uuid(),
  event_hashtag text not null references public.events(hashtag) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  witness_type text not null
    check (witness_type in ('seen', 'confirm', 'deny')),
  latitude double precision,
  longitude double precision,
  gps extensions.geography(Point, 4326),
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now()),
  unique (event_hashtag, user_id, witness_type)
);

create table if not exists public.content_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  content_hash text,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  created_at timestamp with time zone not null default timezone('utc', now()),
  unique (post_id, reporter_id)
);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamp with time zone not null default timezone('utc', now()),
  primary key (follower_id, followed_profile_id)
);

create table if not exists public.followed_tags (
  user_id uuid not null references public.profiles(id) on delete cascade,
  hashtag text not null,
  created_at timestamp with time zone not null default timezone('utc', now()),
  primary key (user_id, hashtag)
);

create table if not exists public.peer_endpoints (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  device_id text,
  protocol text not null default 'spot-p2p-http-v1',
  endpoints text[] not null default '{}',
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now())
);

create table if not exists public.blocklist (
  id uuid primary key default extensions.gen_random_uuid(),
  content_hash text not null unique,
  reason text,
  blocked_by uuid references public.profiles(id) on delete set null,
  source text not null default 'manual',
  blocked_at timestamp with time zone not null default timezone('utc', now())
);

create index if not exists profiles_legacy_pubkey_idx
  on public.profiles (legacy_pubkey);

create index if not exists profiles_device_id_idx
  on public.profiles (device_id);

create index if not exists events_creator_id_idx
  on public.events (creator_id);

create index if not exists posts_created_at_idx
  on public.posts (created_at desc);

create index if not exists posts_user_id_created_at_idx
  on public.posts (user_id, created_at desc);

create index if not exists posts_event_hashtag_created_at_idx
  on public.posts (event_hashtag, created_at desc);

create index if not exists posts_reply_to_id_idx
  on public.posts (reply_to_id);

create index if not exists posts_content_hashes_gin_idx
  on public.posts using gin (content_hashes);

create index if not exists posts_event_tags_gin_idx
  on public.posts using gin (event_tags);

create index if not exists posts_gps_gist_idx
  on public.posts using gist (gps);

create index if not exists witness_signals_event_hashtag_idx
  on public.witness_signals (event_hashtag, created_at desc);

create index if not exists witness_signals_gps_gist_idx
  on public.witness_signals using gist (gps);

create index if not exists content_reports_post_id_idx
  on public.content_reports (post_id, created_at desc);

create index if not exists peer_endpoints_device_id_idx
  on public.peer_endpoints (device_id);

create index if not exists blocklist_content_hash_idx
  on public.blocklist (content_hash);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
before update on public.events
for each row
execute function public.set_updated_at();

drop trigger if exists events_set_location on public.events;
create trigger events_set_location
before insert or update of latitude, longitude on public.events
for each row
execute function public.set_event_location_from_coordinates();

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
before update on public.posts
for each row
execute function public.set_updated_at();

drop trigger if exists posts_set_gps on public.posts;
create trigger posts_set_gps
before insert or update of latitude, longitude on public.posts
for each row
execute function public.set_geography_from_coordinates();

drop trigger if exists witness_signals_set_updated_at on public.witness_signals;
create trigger witness_signals_set_updated_at
before update on public.witness_signals
for each row
execute function public.set_updated_at();

drop trigger if exists witness_signals_set_gps on public.witness_signals;
create trigger witness_signals_set_gps
before insert or update of latitude, longitude on public.witness_signals
for each row
execute function public.set_geography_from_coordinates();

drop trigger if exists peer_endpoints_set_updated_at on public.peer_endpoints;
create trigger peer_endpoints_set_updated_at
before update on public.peer_endpoints
for each row
execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    display_name,
    avatar_seed
  )
  values (
    new.id,
    concat('citizen-', left(new.id::text, 8)),
    left(new.id::text, 12)
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_auth_user();
