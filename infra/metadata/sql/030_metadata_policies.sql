grant usage on schema public to anon, authenticated;

grant select on public.profiles to anon, authenticated;
grant select on public.events to anon, authenticated;
grant select on public.posts to anon, authenticated;
grant select on public.witness_signals to anon, authenticated;
grant select on public.blocklist to anon, authenticated;
grant select on public.peer_endpoints to anon, authenticated;

grant insert, update on public.profiles to authenticated;
grant insert, update on public.events to authenticated;
grant insert, update on public.posts to authenticated;
grant insert, update on public.witness_signals to authenticated;
grant insert, update on public.content_reports to authenticated;
grant select, insert, update, delete on public.peer_endpoints to authenticated;
grant select, insert, update, delete on public.follows to authenticated;
grant select, insert, update, delete on public.followed_tags to authenticated;

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.posts enable row level security;
alter table public.witness_signals enable row level security;
alter table public.content_reports enable row level security;
alter table public.follows enable row level security;
alter table public.followed_tags enable row level security;
alter table public.peer_endpoints enable row level security;
alter table public.blocklist enable row level security;

drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read
on public.profiles
for select
to anon, authenticated
using (true);

drop policy if exists profiles_self_write on public.profiles;
create policy profiles_self_write
on public.profiles
for all
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists events_public_read on public.events;
create policy events_public_read
on public.events
for select
to anon, authenticated
using (true);

drop policy if exists events_authenticated_insert on public.events;
create policy events_authenticated_insert
on public.events
for insert
to authenticated
with check (creator_id is null or (select auth.uid()) = creator_id);

drop policy if exists events_creator_update on public.events;
create policy events_creator_update
on public.events
for update
to authenticated
using (creator_id is null or (select auth.uid()) = creator_id)
with check (creator_id is null or (select auth.uid()) = creator_id);

drop policy if exists posts_public_read on public.posts;
create policy posts_public_read
on public.posts
for select
to anon, authenticated
using (deleted_at is null);

drop policy if exists posts_owner_insert on public.posts;
create policy posts_owner_insert
on public.posts
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists posts_owner_update on public.posts;
create policy posts_owner_update
on public.posts
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists witness_signals_public_read on public.witness_signals;
create policy witness_signals_public_read
on public.witness_signals
for select
to anon, authenticated
using (true);

drop policy if exists witness_signals_owner_write on public.witness_signals;
create policy witness_signals_owner_write
on public.witness_signals
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists content_reports_reporter_read on public.content_reports;
create policy content_reports_reporter_read
on public.content_reports
for select
to authenticated
using ((select auth.uid()) = reporter_id);

drop policy if exists content_reports_reporter_write on public.content_reports;
create policy content_reports_reporter_write
on public.content_reports
for all
to authenticated
using ((select auth.uid()) = reporter_id)
with check ((select auth.uid()) = reporter_id);

drop policy if exists follows_owner_access on public.follows;
create policy follows_owner_access
on public.follows
for all
to authenticated
using ((select auth.uid()) = follower_id)
with check ((select auth.uid()) = follower_id);

drop policy if exists followed_tags_owner_access on public.followed_tags;
create policy followed_tags_owner_access
on public.followed_tags
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists peer_endpoints_public_read on public.peer_endpoints;
create policy peer_endpoints_public_read
on public.peer_endpoints
for select
to anon, authenticated
using (cardinality(endpoints) > 0);

drop policy if exists peer_endpoints_owner_access on public.peer_endpoints;
create policy peer_endpoints_owner_access
on public.peer_endpoints
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists blocklist_public_read on public.blocklist;
create policy blocklist_public_read
on public.blocklist
for select
to anon, authenticated
using (true);
