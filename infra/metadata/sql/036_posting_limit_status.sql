create or replace function public.get_posting_limit_status()
returns table (
  account_age_days integer,
  current_tier_name text,
  thread_limit_per_day integer,
  reply_limit_per_day integer,
  thread_count_today integer,
  reply_count_today integer,
  thread_remaining_today integer,
  reply_remaining_today integer,
  is_posting_blocked boolean,
  posting_block_reason text,
  resets_at timestamp with time zone
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_now timestamp with time zone;
  v_today date;
  v_profile_created_at timestamp with time zone;
  v_account_age_days integer;
  v_today_threads integer := 0;
  v_today_replies integer := 0;
  v_effective_tier_id bigint;
  v_effective_tier_name text;
  v_effective_thread_limit integer;
  v_effective_reply_limit integer;
  v_candidate record;
  v_candidate_active_days integer;
  v_is_posting_blocked boolean := false;
  v_posting_block_reason text;
  v_resets_at timestamp with time zone;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'authenticated user required',
      detail = 'AUTH_REQUIRED',
      hint = 'Sign in again and retry.';
  end if;

  v_now := now();
  v_today := (v_now at time zone 'utc')::date;
  v_resets_at := ((v_today + 1)::timestamp at time zone 'utc');

  select p.created_at
    into v_profile_created_at
  from public.profiles p
  where p.id = v_user_id
  limit 1;

  if v_profile_created_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'profile missing for current user',
      detail = 'PROFILE_REQUIRED',
      hint = 'Refresh your session and try again.';
  end if;

  v_account_age_days := greatest(
    floor(extract(epoch from (v_now - v_profile_created_at)) / 86400)::integer,
    0
  );

  select exists (
      select 1
      from public.account_moderation_flags f
      where f.user_id = v_user_id
        and f.is_posting_blocked
    ),
    (
      select coalesce(
        nullif(btrim(f.reason), ''),
        'This account is blocked from publishing due to spam or bot-like activity.'
      )
      from public.account_moderation_flags f
      where f.user_id = v_user_id
        and f.is_posting_blocked
      limit 1
    )
    into v_is_posting_blocked, v_posting_block_reason;

  for v_candidate in
    select
      t.id,
      t.tier_name,
      t.min_account_age_days,
      t.thread_limit_per_day,
      t.reply_limit_per_day,
      coalesce(r.lookback_days, 0) as lookback_days,
      coalesce(r.min_active_days, 0) as min_active_days
    from public.posting_policy_tiers t
    left join public.posting_policy_activity_requirements r
      on r.tier_id = t.id
    order by t.min_account_age_days desc, t.id desc
  loop
    if v_candidate.min_account_age_days > v_account_age_days then
      continue;
    end if;

    v_candidate_active_days := 0;
    if v_candidate.min_active_days > 0 then
      select count(*)::integer
        into v_candidate_active_days
      from public.account_daily_post_stats s
      where s.user_id = v_user_id
        and s.activity_date >= (
          v_today - greatest(v_candidate.lookback_days - 1, 0)
        )
        and (s.thread_count + s.reply_count) > 0;
    end if;

    if v_candidate.min_active_days <= 0
       or v_candidate_active_days >= v_candidate.min_active_days then
      v_effective_tier_id := v_candidate.id;
      v_effective_tier_name := v_candidate.tier_name;
      v_effective_thread_limit := v_candidate.thread_limit_per_day;
      v_effective_reply_limit := v_candidate.reply_limit_per_day;
      exit;
    end if;
  end loop;

  if v_effective_tier_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'posting policy misconfigured',
      detail = 'POSTING_POLICY_MISSING',
      hint = 'No posting tier is available for this account.';
  end if;

  select
    coalesce(s.thread_count, 0),
    coalesce(s.reply_count, 0)
    into v_today_threads, v_today_replies
  from public.account_daily_post_stats s
  where s.user_id = v_user_id
    and s.activity_date = v_today
  limit 1;

  v_today_threads := coalesce(v_today_threads, 0);
  v_today_replies := coalesce(v_today_replies, 0);

  return query
  select
    v_account_age_days,
    v_effective_tier_name,
    v_effective_thread_limit,
    v_effective_reply_limit,
    v_today_threads,
    v_today_replies,
    greatest(v_effective_thread_limit - v_today_threads, 0),
    greatest(v_effective_reply_limit - v_today_replies, 0),
    v_is_posting_blocked,
    v_posting_block_reason,
    v_resets_at;
end;
$$;

grant execute on function public.get_posting_limit_status() to authenticated;
