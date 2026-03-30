alter table public.profiles
  add column if not exists threads_public boolean not null default true;

alter table public.profiles
  add column if not exists replies_public boolean not null default true;

alter table public.profiles
  add column if not exists footprint_map_public boolean not null default false;
