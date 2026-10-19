-- Run only after explicit deployment/provisioning approval.
begin;
select pg_advisory_xact_lock(hashtextextended('janitra/admin-membership',0));
do $$
declare target uuid;
begin
 select u.id into strict target from auth.users u join public.profiles p on p.id=u.id
 where lower(u.email)='jeffirie12@gmail.com' and u.email_confirmed_at is not null
  and p.is_active and p.deleted_at is null for update of u,p;
 if exists(select 1 from public.role_assignments where role='admin' and is_active and user_id<>target) then
  raise exception 'First Admin already provisioned; review explicitly before adding another';
 end if;
 insert into public.role_assignments(user_id,agency_id,site_id,role)
 values(target,null,null,'admin') on conflict(user_id,agency_id,site_id) do update set is_active=true;
 insert into public.audit_events(actor_id,entity_type,entity_id,action,after_data)
 values(target,'admin_provisioning',target,'insert',jsonb_build_object('role','admin','source','explicit owner approval'));
end $$;
commit;
