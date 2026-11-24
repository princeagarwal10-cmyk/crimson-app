-- Additive setup for the customer management service. Review and test in an
-- isolated project before applying to production. This script does not alter
-- existing catalogue, profile or order rows.
create table if not exists public.crimson_managed_customers (
  user_id uuid primary key,
  login_id text not null,
  display_name text not null,
  normalized_name text generated always as
    (lower(regexp_replace(btrim(display_name), '[[:space:]]+', ' ', 'g'))) stored,
  role text not null check (role in ('customer', 'owner', 'admin')),
  phone text not null default '',
  address text not null default '',
  city text not null default '',
  status text not null default 'provisioning' check (status in ('provisioning','active','disabled','pending_privacy')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crimson_managed_customers_login_key unique (login_id),
  constraint crimson_managed_customers_name_key unique (normalized_name),
  constraint crimson_managed_customers_login_format check (login_id ~ '^[a-z0-9][a-z0-9._-]{2,31}$')
);
alter table public.crimson_managed_customers enable row level security;
revoke all on public.crimson_managed_customers from public, anon, authenticated;
grant select, insert, update, delete on public.crimson_managed_customers to service_role;

-- Existing regular customer names are included in the uniqueness rule.
create unique index if not exists crimson_profiles_unique_customer_name
  on public.crimson_profiles (lower(regexp_replace(btrim(display_name), '[[:space:]]+', ' ', 'g')))
  where role = 'customer';
