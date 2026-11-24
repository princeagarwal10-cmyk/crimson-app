-- Additive photo-first catalogue storage. Existing product data and settings stay unchanged.
-- Run after supabase_crimson_login_roles.sql.

create table if not exists public.crimson_photo_inbox (
  workspace_id text not null,
  id text not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, id)
);

alter table public.crimson_photo_inbox enable row level security;
grant select, insert, update on public.crimson_photo_inbox to authenticated;

drop policy if exists "crimson photo inbox admin read" on public.crimson_photo_inbox;
create policy "crimson photo inbox admin read"
on public.crimson_photo_inbox for select to authenticated
using (private.crimson_is_admin());

drop policy if exists "crimson photo inbox admin insert" on public.crimson_photo_inbox;
create policy "crimson photo inbox admin insert"
on public.crimson_photo_inbox for insert to authenticated
with check (private.crimson_is_admin());

drop policy if exists "crimson photo inbox admin update" on public.crimson_photo_inbox;
create policy "crimson photo inbox admin update"
on public.crimson_photo_inbox for update to authenticated
using (private.crimson_is_admin())
with check (private.crimson_is_admin());

insert into storage.buckets (id, name, public)
values ('crimson-photo-inbox', 'crimson-photo-inbox', false)
on conflict (id) do update set public = false;

drop policy if exists "crimson photo inbox objects admin read" on storage.objects;
create policy "crimson photo inbox objects admin read"
on storage.objects for select to authenticated
using (bucket_id = 'crimson-photo-inbox' and private.crimson_is_admin());

drop policy if exists "crimson photo inbox objects admin upload" on storage.objects;
create policy "crimson photo inbox objects admin upload"
on storage.objects for insert to authenticated
with check (bucket_id = 'crimson-photo-inbox' and private.crimson_is_admin());
