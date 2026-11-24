-- DRAFT: apply only when the customer-safe client and stock-status replacement
-- have been tested and released. Older customer apps cannot read the catalogue
-- after the catalogue policy below is enforced.
begin;
drop policy if exists "crimson catalogue read active users" on public.crimson_catalogue_live;
create policy "crimson catalogue read staff" on public.crimson_catalogue_live
  for select to authenticated
  using ((select private.crimson_current_role()) in ('admin', 'owner', 'staff'));

drop policy if exists "crimson customer orders select" on public.crimson_customer_orders;
create policy "crimson customer orders select" on public.crimson_customer_orders
  for select to authenticated using (
    (select private.crimson_current_role()) in ('admin', 'staff', 'owner')
    or ((select private.crimson_current_role()) = 'customer'
        and customer_user_id = (select auth.uid())
        and payload->>'customerType' = 'regular')
  );

drop policy if exists "crimson customer orders insert" on public.crimson_customer_orders;
create policy "crimson customer orders insert" on public.crimson_customer_orders
  for insert to authenticated with check (
    (select private.crimson_current_role()) in ('admin', 'staff')
    or ((select private.crimson_current_role()) = 'customer'
        and customer_user_id = (select auth.uid())
        and payload->>'customerType' = 'regular'
        and status = 'placed')
  );

drop policy if exists "crimson customer orders update" on public.crimson_customer_orders;
create policy "crimson customer orders update" on public.crimson_customer_orders
  for update to authenticated using (
    (select private.crimson_current_role()) in ('admin', 'staff')
    or ((select private.crimson_current_role()) = 'customer'
        and customer_user_id = (select auth.uid())
        and payload->>'customerType' = 'regular'
        and status = 'placed' and created_at >= now() - interval '10 minutes')
  ) with check (
    (select private.crimson_current_role()) in ('admin', 'staff')
    or ((select private.crimson_current_role()) = 'customer'
        and customer_user_id = (select auth.uid())
        and payload->>'customerType' = 'regular'
        and status in ('placed', 'cancelled')
        and created_at >= now() - interval '10 minutes')
  );
commit;
