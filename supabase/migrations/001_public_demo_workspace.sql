-- GRIT Interview Desk B+
-- Public, synthetic-data demo workspace. No visible login screen.
-- Every visitor obtains an anonymous Supabase Auth session.
-- DO NOT use this schema for real NIAT student records.

begin;

create table if not exists public.grit_demo_workspace (
  id smallint primary key default 1 check (id = 1),
  state jsonb not null,
  version bigint not null default 1 check (version >= 1),
  updated_at timestamptz not null default now()
);

alter table public.grit_demo_workspace enable row level security;

-- The app reads the single synthetic workspace through an anonymous Auth session.
drop policy if exists "Bplus anonymous sessions can read demo workspace"
  on public.grit_demo_workspace;
create policy "Bplus anonymous sessions can read demo workspace"
  on public.grit_demo_workspace
  for select
  to authenticated
  using (coalesce((select auth.jwt() ->> 'is_anonymous') = 'true', false));

grant select on public.grit_demo_workspace to authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.grit_demo_workspace from anon, authenticated;

-- Reject calls that do not originate from an anonymous Supabase Auth session.
create or replace function public.grit_bplus_require_anonymous()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce((select auth.jwt() ->> 'is_anonymous') = 'true', false) is not true then
    raise exception 'BPLUS_ANONYMOUS_SESSION_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.grit_bplus_require_anonymous() from public, anon, authenticated;

-- Initialize once. Later visitors receive the existing shared workspace, not a fresh seed.
create or replace function public.grit_demo_initialize(p_seed jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform public.grit_bplus_require_anonymous();

  if jsonb_typeof(p_seed) <> 'object'
     or jsonb_typeof(p_seed -> 'students') <> 'array'
     or jsonb_typeof(p_seed -> 'interviewers') <> 'array'
     or jsonb_typeof(p_seed -> 'slots') <> 'array'
     or jsonb_typeof(p_seed -> 'bookings') <> 'array'
     or jsonb_typeof(p_seed -> 'audit') <> 'array' then
    raise exception 'INVALID_DEMO_SEED_SHAPE' using errcode = '22023';
  end if;

  if pg_catalog.pg_column_size(p_seed) > 500000 then
    raise exception 'DEMO_SEED_TOO_LARGE' using errcode = '22023';
  end if;

  insert into public.grit_demo_workspace(id, state, version)
  values (1, p_seed, 1)
  on conflict (id) do nothing;

  select pg_catalog.jsonb_build_object('state', state, 'version', version)
    into v_result
    from public.grit_demo_workspace
   where id = 1;

  return v_result;
end;
$$;

-- Read current shared state. RLS also protects direct table reads.
create or replace function public.grit_demo_load_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform public.grit_bplus_require_anonymous();

  select pg_catalog.jsonb_build_object('state', state, 'version', version)
    into v_result
    from public.grit_demo_workspace
   where id = 1;

  if v_result is null then
    raise exception 'DEMO_WORKSPACE_NOT_INITIALIZED' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

-- Optimistic concurrency control: simultaneous visitors cannot silently overwrite each other.
-- The UI reloads the latest state when it receives DEMO_VERSION_CONFLICT.
create or replace function public.grit_demo_save_state(
  p_state jsonb,
  p_expected_version bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_version bigint;
  v_new_version bigint;
begin
  perform public.grit_bplus_require_anonymous();

  if jsonb_typeof(p_state) <> 'object'
     or jsonb_typeof(p_state -> 'students') <> 'array'
     or jsonb_typeof(p_state -> 'interviewers') <> 'array'
     or jsonb_typeof(p_state -> 'slots') <> 'array'
     or jsonb_typeof(p_state -> 'bookings') <> 'array'
     or jsonb_typeof(p_state -> 'audit') <> 'array' then
    raise exception 'INVALID_DEMO_STATE_SHAPE' using errcode = '22023';
  end if;

  if pg_catalog.pg_column_size(p_state) > 1000000 then
    raise exception 'DEMO_STATE_TOO_LARGE' using errcode = '22023';
  end if;

  if pg_catalog.jsonb_array_length(p_state -> 'students') > 100
     or pg_catalog.jsonb_array_length(p_state -> 'interviewers') > 30
     or pg_catalog.jsonb_array_length(p_state -> 'slots') > 1000
     or pg_catalog.jsonb_array_length(p_state -> 'bookings') > 1000
     or pg_catalog.jsonb_array_length(p_state -> 'audit') > 5000 then
    raise exception 'DEMO_STATE_LIMIT_EXCEEDED' using errcode = '22023';
  end if;

  select version into v_current_version
    from public.grit_demo_workspace
   where id = 1
   for update;

  if v_current_version is null then
    raise exception 'DEMO_WORKSPACE_NOT_INITIALIZED' using errcode = 'P0002';
  end if;

  if v_current_version <> p_expected_version then
    raise exception 'DEMO_VERSION_CONFLICT: refresh and retry' using errcode = '40001';
  end if;

  -- Demo-only integrity checks for the current UI state model.
  if exists (
    select 1
      from pg_catalog.jsonb_array_elements(p_state -> 'bookings') b
     where b ->> 'status' in ('booked','checked_in','in_progress','outcome_pending')
       and coalesce(b ->> 'slotId','') = ''
  ) then
    raise exception 'ACTIVE_BOOKING_REQUIRES_SLOT' using errcode = '23514';
  end if;

  if exists (
    select b ->> 'slotId'
      from pg_catalog.jsonb_array_elements(p_state -> 'bookings') b
     where b ->> 'status' in ('booked','checked_in','in_progress','outcome_pending')
     group by b ->> 'slotId'
    having count(*) > 1
  ) then
    raise exception 'SLOT_ALREADY_HAS_ACTIVE_BOOKING' using errcode = '23505';
  end if;

  if exists (
    select 1
      from pg_catalog.jsonb_array_elements(p_state -> 'bookings') b
     where b ->> 'status' in ('booked','checked_in','in_progress','outcome_pending')
       and not exists (
         select 1
           from pg_catalog.jsonb_array_elements(p_state -> 'slots') s
          where s ->> 'id' = b ->> 'slotId'
            and s ->> 'status' = 'booked'
            and s ->> 'bookingId' = b ->> 'id'
       )
  ) then
    raise exception 'ACTIVE_BOOKING_SLOT_MISMATCH' using errcode = '23514';
  end if;

  update public.grit_demo_workspace
     set state = p_state,
         version = version + 1,
         updated_at = now()
   where id = 1
   returning version into v_new_version;

  return v_new_version;
end;
$$;

revoke all on function public.grit_demo_initialize(jsonb) from public, anon;
revoke all on function public.grit_demo_load_state() from public, anon;
revoke all on function public.grit_demo_save_state(jsonb, bigint) from public, anon;
grant execute on function public.grit_demo_initialize(jsonb) to authenticated;
grant execute on function public.grit_demo_load_state() to authenticated;
grant execute on function public.grit_demo_save_state(jsonb, bigint) to authenticated;

-- Realtime is enabled only for the single shared synthetic workspace row.
do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'grit_demo_workspace'
     ) then
    execute 'alter publication supabase_realtime add table public.grit_demo_workspace';
  end if;
end;
$$;

commit;
