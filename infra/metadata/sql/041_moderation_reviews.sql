alter table public.content_reports
  add column if not exists details text,
  add column if not exists status text,
  add column if not exists resolution_note text,
  add column if not exists reviewed_at timestamp with time zone,
  add column if not exists reviewed_by_auth_user_id uuid,
  add column if not exists reviewed_by_email text,
  add column if not exists updated_at timestamp with time zone;

update public.content_reports
set
  status = coalesce(nullif(status, ''), 'open'),
  updated_at = coalesce(updated_at, created_at)
where status is null
   or status = ''
   or updated_at is null;

alter table public.content_reports
  alter column status set default 'open';

alter table public.content_reports
  alter column status set not null;

alter table public.content_reports
  alter column updated_at set default timezone('utc', now());

alter table public.content_reports
  alter column updated_at set not null;

alter table public.content_reports
  drop constraint if exists content_reports_status_check;

alter table public.content_reports
  add constraint content_reports_status_check
  check (status in ('open', 'under_review', 'action_taken', 'dismissed'));

drop trigger if exists content_reports_set_updated_at on public.content_reports;
create trigger content_reports_set_updated_at
before update on public.content_reports
for each row
execute function public.set_updated_at();

create table if not exists public.user_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete set null,
  reported_legacy_pubkey text not null,
  reason text not null
    check (
      reason in (
        'harassment',
        'hate',
        'sexual_content',
        'violence',
        'spam',
        'impersonation',
        'other'
      )
    ),
  details text,
  status text not null default 'open'
    check (status in ('open', 'under_review', 'action_taken', 'dismissed')),
  resolution_note text,
  reviewed_at timestamp with time zone,
  reviewed_by_auth_user_id uuid,
  reviewed_by_email text,
  created_at timestamp with time zone not null default timezone('utc', now()),
  updated_at timestamp with time zone not null default timezone('utc', now()),
  unique (reporter_id, reported_legacy_pubkey)
);

create index if not exists content_reports_status_created_at_idx
  on public.content_reports (status, created_at desc);

create index if not exists user_reports_status_created_at_idx
  on public.user_reports (status, created_at desc);

create index if not exists user_reports_reported_user_id_idx
  on public.user_reports (reported_user_id, created_at desc);

create index if not exists user_reports_reported_pubkey_idx
  on public.user_reports (reported_legacy_pubkey, created_at desc);

drop trigger if exists user_reports_set_updated_at on public.user_reports;
create trigger user_reports_set_updated_at
before update on public.user_reports
for each row
execute function public.set_updated_at();

alter table public.account_moderation_flags
  add column if not exists moderated_by_auth_user_id uuid,
  add column if not exists moderated_by_email text;

grant select on public.content_reports to authenticated;
grant select on public.user_reports to authenticated;

revoke insert, update on public.content_reports from authenticated;

alter table public.user_reports enable row level security;

drop policy if exists content_reports_reporter_write on public.content_reports;

drop policy if exists content_reports_reporter_read on public.content_reports;
create policy content_reports_reporter_read
on public.content_reports
for select
to authenticated
using ((select auth.uid()) = reporter_id);

drop policy if exists user_reports_reporter_read on public.user_reports;
create policy user_reports_reporter_read
on public.user_reports
for select
to authenticated
using ((select auth.uid()) = reporter_id);

create or replace function public.submit_content_report(
  p_post_id uuid,
  p_content_hash text default null,
  p_reason text default 'harmful',
  p_details text default null
)
returns public.content_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter_id uuid;
  v_reason text;
  v_details text;
  v_row public.content_reports%rowtype;
begin
  v_reporter_id := auth.uid();
  if v_reporter_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'authenticated user required',
      detail = 'AUTH_REQUIRED',
      hint = 'Sign in again and retry.';
  end if;

  if p_post_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'post id required',
      detail = 'POST_ID_REQUIRED',
      hint = 'Select the reported content again and retry.';
  end if;

  v_reason := coalesce(nullif(btrim(p_reason), ''), 'harmful');
  v_details := nullif(btrim(coalesce(p_details, '')), '');

  insert into public.content_reports (
    post_id,
    content_hash,
    reporter_id,
    reason,
    details,
    status,
    resolution_note,
    reviewed_at,
    reviewed_by_auth_user_id,
    reviewed_by_email
  )
  values (
    p_post_id,
    nullif(btrim(coalesce(p_content_hash, '')), ''),
    v_reporter_id,
    v_reason,
    v_details,
    'open',
    null,
    null,
    null,
    null
  )
  on conflict (post_id, reporter_id) do update
    set content_hash = excluded.content_hash,
        reason = excluded.reason,
        details = excluded.details,
        status = 'open',
        resolution_note = null,
        reviewed_at = null,
        reviewed_by_auth_user_id = null,
        reviewed_by_email = null,
        updated_at = timezone('utc', now())
  returning *
    into v_row;

  return v_row;
end;
$$;

create or replace function public.submit_user_report(
  p_reported_user_id uuid default null,
  p_reported_legacy_pubkey text default null,
  p_reason text default 'other',
  p_details text default null
)
returns public.user_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter_id uuid;
  v_reported_pubkey text;
  v_reason text;
  v_details text;
  v_row public.user_reports%rowtype;
begin
  v_reporter_id := auth.uid();
  if v_reporter_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'authenticated user required',
      detail = 'AUTH_REQUIRED',
      hint = 'Sign in again and retry.';
  end if;

  v_reported_pubkey := nullif(btrim(coalesce(p_reported_legacy_pubkey, '')), '');
  if v_reported_pubkey is null then
    raise exception using
      errcode = 'P0001',
      message = 'reported user required',
      detail = 'REPORTED_USER_REQUIRED',
      hint = 'Select the abusive account again and retry.';
  end if;

  v_reason := coalesce(nullif(btrim(p_reason), ''), 'other');
  v_details := nullif(btrim(coalesce(p_details, '')), '');

  insert into public.user_reports (
    reporter_id,
    reported_user_id,
    reported_legacy_pubkey,
    reason,
    details,
    status,
    resolution_note,
    reviewed_at,
    reviewed_by_auth_user_id,
    reviewed_by_email
  )
  values (
    v_reporter_id,
    p_reported_user_id,
    v_reported_pubkey,
    v_reason,
    v_details,
    'open',
    null,
    null,
    null,
    null
  )
  on conflict (reporter_id, reported_legacy_pubkey) do update
    set reported_user_id = excluded.reported_user_id,
        reason = excluded.reason,
        details = excluded.details,
        status = 'open',
        resolution_note = null,
        reviewed_at = null,
        reviewed_by_auth_user_id = null,
        reviewed_by_email = null,
        updated_at = timezone('utc', now())
  returning *
    into v_row;

  return v_row;
end;
$$;

grant execute on function public.submit_content_report(uuid, text, text, text)
  to authenticated;

grant execute on function public.submit_user_report(uuid, text, text, text)
  to authenticated;
