-- Stage 1 only: add a customer-safe read endpoint. The old table policy is
-- deliberately not changed by this script; enforce only after all customer
-- clients have upgraded and the endpoint has been tested with real sessions.
create or replace function public.crimson_customer_catalogue(requested_workspace text)
returns table (payload jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select c.payload - 'customerOrders' - 'stockVouchers' - 'stockItems' - 'photoInbox'
  from public.crimson_catalogue_live c
  where auth.uid() is not null
    and private.crimson_current_role() = 'customer'
    and requested_workspace = 'default'
    and c.workspace_id = 'default';
$$;
revoke all on function public.crimson_customer_catalogue(text) from public, anon;
grant execute on function public.crimson_customer_catalogue(text) to authenticated;
