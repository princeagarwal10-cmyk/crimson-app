-- Crimson shared customer orders
-- Run this once in Supabase SQL Editor.
-- It stores customer/admin orders separately from the catalogue payload so order numbers stay unique.

create schema if not exists private;

create table if not exists public.crimson_order_counters (
  workspace_id text not null,
  order_year integer not null,
  last_number integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, order_year)
);

alter table public.crimson_order_counters enable row level security;

revoke all on public.crimson_order_counters from anon, authenticated;

drop policy if exists "crimson order counters admin read" on public.crimson_order_counters;
create policy "crimson order counters admin read"
on public.crimson_order_counters
for select
to authenticated
using ((select private.crimson_current_role()) = 'admin');

create table if not exists public.crimson_customer_orders (
  id text primary key,
  workspace_id text not null default 'default',
  order_number text,
  customer_user_id uuid not null references auth.users(id) on delete cascade,
  customer_email text not null default '',
  status text not null default 'placed',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crimson_customer_orders_status_check check (
    status in ('draft', 'placed', 'confirmed', 'packed', 'dispatched', 'delivered', 'cancelled', 'rejected')
  )
);

create unique index if not exists crimson_customer_orders_workspace_number_idx
on public.crimson_customer_orders (workspace_id, order_number)
where order_number is not null and btrim(order_number) <> '';

create index if not exists crimson_customer_orders_workspace_created_idx
on public.crimson_customer_orders (workspace_id, created_at desc);

create index if not exists crimson_customer_orders_customer_idx
on public.crimson_customer_orders (customer_user_id, created_at desc);

create index if not exists crimson_customer_orders_status_idx
on public.crimson_customer_orders (workspace_id, status, created_at desc);

create or replace function private.crimson_assign_customer_order_number()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_year integer;
  v_next integer;
begin
  if new.id is null or btrim(new.id) = '' then
    new.id := replace(gen_random_uuid()::text, '-', '');
  end if;

  new.workspace_id := coalesce(nullif(btrim(new.workspace_id), ''), 'default');
  new.status := coalesce(nullif(btrim(new.status), ''), 'placed');
  new.updated_at := now();

  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
  end if;

  if new.order_number is null or btrim(new.order_number) = '' or new.order_number like 'LOCAL-%' then
    v_year := extract(year from timezone('utc', now()))::integer;

    -- Older or manually numbered orders may be ahead of the counter. Keep
    -- the counter row locked and skip every number already in use.
    loop
      insert into public.crimson_order_counters (workspace_id, order_year, last_number, updated_at)
      values (new.workspace_id, v_year, 1, now())
      on conflict (workspace_id, order_year)
      do update set
        last_number = public.crimson_order_counters.last_number + 1,
        updated_at = now()
      returning last_number into v_next;

      new.order_number := 'ORD-' || v_year::text || '-' || lpad(v_next::text, greatest(5, length(v_next::text)), '0');
      exit when not exists (
        select 1 from public.crimson_customer_orders existing
        where existing.workspace_id = new.workspace_id
          and existing.order_number = new.order_number
      );
    end loop;
  end if;

  new.payload := coalesce(new.payload, '{}'::jsonb)
    || jsonb_build_object(
      'id', new.id,
      'orderNumber', new.order_number,
      'order_number', new.order_number,
      'status', new.status,
      'createdAt', to_char(new.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'updatedAt', to_char(new.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    );

  return new;
end;
$$;

revoke all on function private.crimson_assign_customer_order_number() from public, anon, authenticated;

drop trigger if exists crimson_customer_orders_number_trigger on public.crimson_customer_orders;
create trigger crimson_customer_orders_number_trigger
before insert or update on public.crimson_customer_orders
for each row execute function private.crimson_assign_customer_order_number();

alter table public.crimson_customer_orders enable row level security;

grant select, insert, update on public.crimson_customer_orders to authenticated;

drop policy if exists "crimson customer orders select" on public.crimson_customer_orders;
drop policy if exists "crimson customer orders insert" on public.crimson_customer_orders;
drop policy if exists "crimson customer orders update" on public.crimson_customer_orders;

create policy "crimson customer orders select"
on public.crimson_customer_orders
for select
to authenticated
using (
  (select private.crimson_current_role()) in ('admin', 'staff', 'owner')
  or customer_user_id = (select auth.uid())
);

create policy "crimson customer orders insert"
on public.crimson_customer_orders
for insert
to authenticated
with check (
  (select private.crimson_current_role()) in ('customer', 'owner', 'staff', 'admin')
  and customer_user_id = (select auth.uid())
);

create policy "crimson customer orders update"
on public.crimson_customer_orders
for update
to authenticated
using (
  (select private.crimson_current_role()) in ('admin', 'staff')
  or (
    customer_user_id = (select auth.uid())
    and status = 'placed'
    and created_at >= now() - interval '10 minutes'
  )
)
with check (
  (select private.crimson_current_role()) in ('admin', 'staff')
  or (
    customer_user_id = (select auth.uid())
    and status in ('placed', 'cancelled')
    and created_at >= now() - interval '10 minutes'
  )
);
