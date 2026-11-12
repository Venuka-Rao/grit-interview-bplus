-- Read-only verification for GRIT B+ demo.
-- Run after 001_public_demo_workspace.sql.

-- 1. Table exists.
select
  to_regclass('public.grit_demo_workspace') is not null as table_exists;

-- 2. RLS is enabled (must return true).
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'grit_demo_workspace';

-- 3. Required RPC functions exist (3 rows expected).
select
  routine_name,
  routine_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'grit_demo_initialize',
    'grit_demo_load_state',
    'grit_demo_save_state',
    'grit_bplus_require_anonymous'
  )
order by routine_name;

-- 4. Direct table grants. SELECT to authenticated is expected.
-- INSERT/UPDATE/DELETE must NOT be granted to anon/authenticated.
select
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'grit_demo_workspace'
order by grantee, privilege_type;

-- 5. Realtime publication membership (1 row expected).
select
  pubname,
  schemaname,
  tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'grit_demo_workspace';

-- 6. Read-only summary (row will appear only after the first browser visit).
select
  id,
  version,
  jsonb_array_length(state -> 'students') as students,
  jsonb_array_length(state -> 'interviewers') as interviewers,
  jsonb_array_length(state -> 'slots') as slots,
  jsonb_array_length(state -> 'bookings') as bookings,
  updated_at
from public.grit_demo_workspace
where id = 1;
