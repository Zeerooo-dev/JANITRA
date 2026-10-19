\set ON_ERROR_STOP on
begin;
-- Run through a trusted database connection after the approved Auth invitation.
do $$
declare first_user uuid;
begin
  select id into strict first_user from auth.users where lower(email)='jeffirie12@gmail.com';
  if exists(select 1 from public.role_assignments where user_id=first_user) then
    raise exception 'This account already has workplace access';
  end if;
  if exists(select 1 from janitra_private.supervisor_bootstrap_grants where user_id<>first_user)
    or exists(select 1 from public.role_assignments where role='supervisor') then
    raise exception 'First Supervisor was already authorized; use scoped invitations';
  end if;
  insert into janitra_private.supervisor_bootstrap_grants(user_id) values(first_user)
    on conflict(user_id) do nothing;
end $$;
commit;
