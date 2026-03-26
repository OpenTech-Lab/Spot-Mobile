alter table public.posts replica identity full;
alter table public.witness_signals replica identity full;
alter table public.blocklist replica identity full;
alter table public.events replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'posts'
  ) then
    execute 'alter publication supabase_realtime add table public.posts';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'witness_signals'
  ) then
    execute 'alter publication supabase_realtime add table public.witness_signals';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'blocklist'
  ) then
    execute 'alter publication supabase_realtime add table public.blocklist';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'events'
  ) then
    execute 'alter publication supabase_realtime add table public.events';
  end if;
end
$$;
