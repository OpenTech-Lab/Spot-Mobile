alter table public.profiles
  add column if not exists avatar_content_hash text;
