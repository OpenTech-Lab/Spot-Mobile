create or replace function public.soft_delete_post(
  p_requested_post_id text default null,
  p_content_hash text default null
)
returns public.posts
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
  v_legacy_pubkey text;
  v_target public.posts%rowtype;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'authenticated user required';
  end if;

  select legacy_pubkey
    into v_legacy_pubkey
  from public.profiles
  where id = v_user_id;

  if v_legacy_pubkey is null or btrim(v_legacy_pubkey) = '' then
    raise exception 'current profile missing legacy pubkey';
  end if;

  if p_requested_post_id is not null and btrim(p_requested_post_id) <> '' then
    select p.*
      into v_target
    from public.posts p
    join public.profiles owner on owner.id = p.user_id
    where p.deleted_at is null
      and p.id::text = btrim(p_requested_post_id)
      and (
        p.user_id = v_user_id
        or owner.legacy_pubkey = v_legacy_pubkey
      )
    limit 1;
  end if;

  if not found and p_content_hash is not null and btrim(p_content_hash) <> '' then
    select p.*
      into v_target
    from public.posts p
    join public.profiles owner on owner.id = p.user_id
    where p.deleted_at is null
      and btrim(p_content_hash) = any (p.content_hashes)
      and (
        p.user_id = v_user_id
        or owner.legacy_pubkey = v_legacy_pubkey
      )
    order by p.created_at desc
    limit 1;
  end if;

  if not found then
    raise exception 'post not found for deletion';
  end if;

  update public.posts
  set deleted_at = timezone('utc', now())
  where id = v_target.id
  returning *
    into v_target;

  return v_target;
end;
$$;

grant execute on function public.soft_delete_post(text, text) to authenticated;
