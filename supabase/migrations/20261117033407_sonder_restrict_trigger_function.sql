-- The sign-up trigger function is never called directly. Remove the default PUBLIC execute grant
-- so it is not exposed as an RPC; the auth service role keeps execute for the trigger itself.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.handle_new_user() to supabase_auth_admin;
  end if;
end $$;
