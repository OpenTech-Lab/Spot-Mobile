with ranked_witnesses as (
  select
    id,
    row_number() over (
      partition by event_hashtag, user_id
      order by updated_at desc, created_at desc, id desc
    ) as row_num
  from public.witness_signals
)
delete from public.witness_signals witness
using ranked_witnesses ranked
where witness.id = ranked.id
  and ranked.row_num > 1;

alter table public.witness_signals
  drop constraint if exists witness_signals_event_hashtag_user_id_witness_type_key;

create unique index if not exists witness_signals_event_user_idx
  on public.witness_signals (event_hashtag, user_id);

create or replace function public.set_witness_signal(
  p_event_hashtag text,
  p_witness_type text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns public.witness_signals
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hashtag text;
  v_requested_type text;
  v_existing public.witness_signals%rowtype;
  v_result public.witness_signals%rowtype;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required';
  end if;

  v_hashtag = nullif(lower(trim(p_event_hashtag)), '');
  v_requested_type = nullif(lower(trim(p_witness_type)), '');

  if v_hashtag is null then
    raise exception 'hashtag is required';
  end if;

  if v_requested_type not in ('seen', 'confirm', 'deny') then
    raise exception 'valid witness_type is required';
  end if;

  select *
    into v_existing
  from public.witness_signals
  where event_hashtag = v_hashtag
    and user_id = auth.uid();

  if found and v_existing.witness_type = v_requested_type then
    delete from public.witness_signals
    where id = v_existing.id;

    return null;
  end if;

  insert into public.witness_signals (
    event_hashtag,
    user_id,
    witness_type,
    latitude,
    longitude,
    updated_at
  )
  values (
    v_hashtag,
    auth.uid(),
    v_requested_type,
    p_latitude,
    p_longitude,
    timezone('utc', now())
  )
  on conflict (event_hashtag, user_id) do update
    set witness_type = excluded.witness_type,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        updated_at = timezone('utc', now())
  returning *
    into v_result;

  return v_result;
end;
$$;

grant execute on function public.set_witness_signal(
  text,
  text,
  double precision,
  double precision
) to authenticated;
