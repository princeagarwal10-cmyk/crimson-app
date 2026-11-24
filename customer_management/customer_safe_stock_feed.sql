-- Status-only customer catalogue. No quantity, voucher, customer order, party,
-- or stock-item records leave this function.
create or replace function public.crimson_customer_catalogue(requested_workspace text)
returns table (payload jsonb)
language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  with source as (
    select c.payload as document
    from public.crimson_catalogue_live c
    where auth.uid() is not null and private.crimson_current_role() = 'customer'
      and requested_workspace = 'default' and c.workspace_id = 'default'
  ), movements as (
    select concat(coalesce(i->>'productId',''), '|',
      lower(regexp_replace(btrim(coalesce(i->>'size','')), '[[:space:]]+', ' ', 'g')), '|',
      lower(regexp_replace(btrim(coalesce(i->>'finish','')), '[[:space:]]+', ' ', 'g'))) as key,
      sum((case when coalesce(i->>'quantity','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (i->>'quantity')::numeric else 0 end) *
        case v->>'type' when 'outward' then -1 when 'transfer' then 0 else 1 end) as physical
    from source s
    cross join lateral jsonb_array_elements(coalesce(s.document->'stockVouchers', '[]'::jsonb)) v
    cross join lateral jsonb_array_elements(coalesce(v->'items', '[]'::jsonb)) i
    group by 1
  ), statuses as (
    select coalesce(jsonb_object_agg(m.key, case when m.physical >= 50 then 'inStock'
      when m.physical > 0 then 'lowStock' else 'outOfStock' end), '{}'::jsonb) as data
    from movements m
  )
  select (s.document - 'customerOrders' - 'stockVouchers' - 'stockItems' - 'photoInbox')
         || jsonb_build_object('customerStockStatuses', statuses.data)
  from source s cross join statuses;
$$;
revoke all on function public.crimson_customer_catalogue(text) from public, anon;
grant execute on function public.crimson_customer_catalogue(text) to authenticated;
