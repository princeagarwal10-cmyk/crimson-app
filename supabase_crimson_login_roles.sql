-- Crimson Decore proper login and role-based catalogue access.
-- Safe v2: avoids recursive profile RLS checks and creates the live table if missing.
-- Run this in Supabase SQL Editor after enabling Email/Password Auth.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
grant usage on schema public to authenticated;

create table if not exists public.crimson_catalogue_live (
  workspace_id text primary key default 'default',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.crimson_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'customer' check (role in ('customer', 'owner', 'admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_crimson_profiles_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_crimson_profiles_updated_at() from public;

drop trigger if exists crimson_profiles_set_updated_at on public.crimson_profiles;
create trigger crimson_profiles_set_updated_at
before update on public.crimson_profiles
for each row execute function public.set_crimson_profiles_updated_at();

-- Private helper functions are used by RLS policies to avoid infinite recursion
-- when checking whether the current user is an active admin.
create or replace function private.crimson_current_role()
returns text
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select p.role
  from public.crimson_profiles p
  where p.user_id = auth.uid()
    and p.is_active = true
  limit 1;
$$;

create or replace function private.crimson_is_admin()
returns boolean
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select coalesce(private.crimson_current_role() = 'admin', false);
$$;

revoke all on function private.crimson_current_role() from public;
revoke all on function private.crimson_is_admin() from public;
grant execute on function private.crimson_current_role() to authenticated;
grant execute on function private.crimson_is_admin() to authenticated;

alter table public.crimson_profiles enable row level security;
alter table public.crimson_catalogue_live enable row level security;

grant select on public.crimson_profiles to authenticated;
grant select, insert, update on public.crimson_catalogue_live to authenticated;

-- Reset older policies so customer/owner cannot write by accident.
drop policy if exists "crimson catalogue live read" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue live create" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue live update" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue read authenticated" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue create authenticated" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue update authenticated" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue read active users" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue admin insert" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue admin update" on public.crimson_catalogue_live;

drop policy if exists "crimson profiles read own" on public.crimson_profiles;
drop policy if exists "crimson profiles admin read all" on public.crimson_profiles;
drop policy if exists "crimson profiles admin insert" on public.crimson_profiles;
drop policy if exists "crimson profiles admin update" on public.crimson_profiles;
drop policy if exists "crimson profiles admin delete" on public.crimson_profiles;

create policy "crimson profiles read own"
on public.crimson_profiles
for select
to authenticated
using (user_id = auth.uid());

create policy "crimson profiles admin read all"
on public.crimson_profiles
for select
to authenticated
using (private.crimson_is_admin());

create policy "crimson profiles admin insert"
on public.crimson_profiles
for insert
to authenticated
with check (private.crimson_is_admin());

create policy "crimson profiles admin update"
on public.crimson_profiles
for update
to authenticated
using (private.crimson_is_admin())
with check (private.crimson_is_admin());

create policy "crimson profiles admin delete"
on public.crimson_profiles
for delete
to authenticated
using (private.crimson_is_admin());

create policy "crimson catalogue read active users"
on public.crimson_catalogue_live
for select
to authenticated
using (private.crimson_current_role() in ('customer', 'owner', 'admin'));

create policy "crimson catalogue admin insert"
on public.crimson_catalogue_live
for insert
to authenticated
with check (private.crimson_is_admin());

create policy "crimson catalogue admin update"
on public.crimson_catalogue_live
for update
to authenticated
using (private.crimson_is_admin())
with check (private.crimson_is_admin());

-- IMPORTANT: after creating your owner/admin user in Authentication,
-- run this example once in SQL Editor, replacing the email.
-- This first insert must be done from SQL Editor because no admin exists yet.
--
-- insert into public.crimson_profiles (user_id, display_name, role, is_active)
-- select id, coalesce(raw_user_meta_data->>'display_name', email), 'admin', true
-- from auth.users
-- where email = 'YOUR_OWNER_EMAIL_HERE'
-- on conflict (user_id) do update
-- set role = 'admin', is_active = true, display_name = excluded.display_name;
--
-- Add customer/owner users like this after creating them in Authentication:
--
-- insert into public.crimson_profiles (user_id, display_name, role, is_active)
-- select id, email, 'customer', true
-- from auth.users
-- where email = 'CUSTOMER_EMAIL_HERE'
-- on conflict (user_id) do update
-- set role = 'customer', is_active = true, display_name = excluded.display_name;
