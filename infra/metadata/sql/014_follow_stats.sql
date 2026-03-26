create or replace function public.get_follow_stats(p_profile_id uuid)
returns table (
  profile_id uuid,
  follower_count bigint,
  following_count bigint,
  is_following_by_me boolean
)
language sql
security definer
set search_path = public, extensions
as $$
  select
    p_profile_id as profile_id,
    (
      select count(*)
      from public.follows
      where followed_profile_id = p_profile_id
    )::bigint as follower_count,
    (
      select count(*)
      from public.follows
      where follower_id = p_profile_id
    )::bigint as following_count,
    case
      when auth.uid() is null then false
      else exists(
        select 1
        from public.follows
        where follower_id = auth.uid()
          and followed_profile_id = p_profile_id
      )
    end as is_following_by_me;
$$;

grant execute on function public.get_follow_stats(uuid) to authenticated;
