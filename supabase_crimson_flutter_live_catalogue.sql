-- Crimson Flutter Catalogue V1 live bridge.
-- Run this in the existing Supabase project SQL editor.
-- It keeps the new Flutter catalogue separate from older Crimson/FitBook tables.

create table if not exists public.crimson_catalogue_live (
  workspace_id text primary key default 'default',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.crimson_catalogue_live enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update on public.crimson_catalogue_live to authenticated;

drop policy if exists "crimson catalogue live read" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue live create" on public.crimson_catalogue_live;
drop policy if exists "crimson catalogue live update" on public.crimson_catalogue_live;

create policy "crimson catalogue live read"
on public.crimson_catalogue_live
for select
to authenticated
using (true);

create policy "crimson catalogue live create"
on public.crimson_catalogue_live
for insert
to authenticated
with check (true);

create policy "crimson catalogue live update"
on public.crimson_catalogue_live
for update
to authenticated
using (true)
with check (true);
