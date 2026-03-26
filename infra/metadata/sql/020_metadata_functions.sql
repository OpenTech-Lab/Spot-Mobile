create or replace function public.ensure_event_exists(
  p_hashtag text,
  p_title text default null,
  p_description text default null,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns public.events
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_event public.events%rowtype;
  v_hashtag text;
begin
  v_hashtag = nullif(lower(trim(p_hashtag)), '');

  if v_hashtag is null then
    raise exception 'hashtag is required';
  end if;

  insert into public.events (
    hashtag,
    title,
    description,
    creator_id,
    latitude,
    longitude
  )
  values (
    v_hashtag,
    p_title,
    p_description,
    auth.uid(),
    p_latitude,
    p_longitude
  )
  on conflict (hashtag) do update
    set title = coalesce(public.events.title, excluded.title),
        description = coalesce(public.events.description, excluded.description),
        latitude = coalesce(public.events.latitude, excluded.latitude),
        longitude = coalesce(public.events.longitude, excluded.longitude)
  returning * into v_event;

  return v_event;
end;
$$;

grant execute on function public.ensure_event_exists(
  text,
  text,
  text,
  double precision,
  double precision
) to authenticated;

create or replace function public.nearby_posts(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_meters integer default 5000,
  p_limit integer default 50
)
returns setof public.posts
language sql
stable
set search_path = public, extensions
as $$
  select p.*
  from public.posts p
  where p.deleted_at is null
    and p.gps is not null
    and not exists (
      select 1
      from public.blocklist b
      where b.content_hash = any (p.content_hashes)
    )
    and extensions.st_dwithin(
      p.gps,
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude),
        4326
      )::extensions.geography,
      greatest(p_radius_meters, 1)
    )
  order by p.created_at desc
  limit greatest(p_limit, 1);
$$;

grant execute on function public.nearby_posts(
  double precision,
  double precision,
  integer,
  integer
) to anon, authenticated;

create or replace function public.trending_posts(
  p_limit integer default 50
)
returns setof public.posts
language sql
stable
set search_path = public
as $$
  select p.*
  from public.posts p
  where p.deleted_at is null
    and not exists (
      select 1
      from public.blocklist b
      where b.content_hash = any (p.content_hashes)
    )
  order by (
    (p.view_count * 0.30) +
    (p.like_count * 1.20) +
    (p.reply_count * 0.90)
  ) desc,
  p.created_at desc
  limit greatest(p_limit, 1);
$$;

grant execute on function public.trending_posts(integer) to anon, authenticated;
