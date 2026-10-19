begin;

alter table public.role_assignments alter column agency_id drop not null;
alter table public.role_assignments drop constraint role_assignments_role_check;
alter table public.role_assignments drop constraint role_assignments_check;
alter table public.role_assignments add constraint role_assignments_role_check
 check(role in ('admin','supervisor','personnel'));
alter table public.role_assignments add constraint role_assignments_scope_check
 check((role='admin' and agency_id is null and site_id is null)
 or (role<>'admin' and agency_id is not null and (role='supervisor' or site_id is not null)));

alter table public.profiles add column deleted_at timestamptz;
-- Historical records keep their profile foreign keys after Auth access is removed.
alter table public.profiles drop constraint profiles_id_fkey;

-- The original one-person bootstrap must not bypass Admin-managed Supervisor access.
create or replace function public.needs_company_setup() returns boolean
language sql stable security definer set search_path='' as $$ select false; $$;
revoke execute on function public.setup_manpower_company(text,text) from authenticated;

create function janitra_private.is_admin(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
  where p.id=p_user and p.is_active and p.deleted_at is null and r.role='admin' and r.is_active);
$$;
revoke all on function janitra_private.is_admin(uuid) from public,anon,authenticated,service_role;

create or replace function janitra_private.manager_has_scope(p_actor uuid,p_agency uuid,p_site uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.is_admin(p_actor) or exists(
  select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
  where p.id=p_actor and p.is_active and p.deleted_at is null and r.is_active
   and r.role='supervisor' and r.agency_id=p_agency and (r.site_id is null or r.site_id=p_site));
$$;
create or replace function janitra_private.has_site_role(target_agency uuid,target_site uuid,required_roles text[])
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and (janitra_private.is_admin(auth.uid()) or exists(
   select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
   where r.user_id=auth.uid() and p.is_active and p.deleted_at is null and r.is_active
    and r.agency_id=target_agency and r.role=any(required_roles)
    and (r.site_id is null or r.site_id=target_site)));
$$;
create or replace function janitra_private.is_agency_member(target_agency uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and (janitra_private.is_admin(auth.uid()) or exists(
   select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
   where r.user_id=auth.uid() and p.is_active and p.deleted_at is null and r.is_active and r.agency_id=target_agency));
$$;

create or replace function janitra_private.emit_work_event(p_task uuid,p_actor uuid,p_event text,p_details jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare t public.task_instances%rowtype;
begin
 select * into strict t from public.task_instances where id=p_task;
 insert into public.task_events(task_id,actor_id,agency_id,site_id,event,details) values(t.id,p_actor,t.agency_id,t.site_id,p_event,p_details);
 if p_event='submitted' then
  insert into public.task_notifications(task_id,recipient_id,agency_id,site_id,message)
  select distinct t.id,r.user_id,t.agency_id,t.site_id,t.personnel_name||' submitted '||t.activity_name||'.'
  from public.role_assignments r join public.profiles p on p.id=r.user_id
  where p.is_active and p.deleted_at is null and r.is_active and
   (r.role='admin' or (r.role='supervisor' and r.agency_id=t.agency_id and (r.site_id is null or r.site_id=t.site_id)));
 elsif p_event<>'scheduled' then
  insert into public.task_notifications(task_id,recipient_id,agency_id,site_id,message)
  values(t.id,t.user_id,t.agency_id,t.site_id,t.activity_name||': '||replace(p_event,'_',' ')||'.');
 end if;
end $$;

do $$
declare definition text;
 task_lock text := 'user_id=p_actor and agency_id=t.agency_id and (site_id is null or site_id=t.site_id) and is_active and role=''supervisor''';
 scope_lock text := 'user_id=p_actor and role=''supervisor'' and is_active and agency_id=agency and (site_id is null or site_id=site)';
begin
 definition:=pg_get_functiondef('public.workflow_command_without_checklists(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(definition,task_lock)=0 or strpos(definition,scope_lock)=0 then
  raise exception 'Unexpected workflow authorization definition';
 end if;
 -- Extend the existing authority locks without replacing workflow/deadline logic.
 definition:=replace(definition,task_lock,
  'user_id=p_actor and is_active and (role=''admin'' or (role=''supervisor'' and agency_id=t.agency_id and (site_id is null or site_id=t.site_id)))');
 definition:=replace(definition,scope_lock,
  'user_id=p_actor and is_active and (role=''admin'' or (role=''supervisor'' and agency_id=agency and (site_id is null or site_id=site)))');
 execute definition;
end $$;

create function janitra_private.protect_last_admin() returns trigger
language plpgsql security definer set search_path='' as $$
declare target uuid; removing boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('janitra/admin-membership',0));
 if tg_table_name='profiles' then
  target:=old.id;
  if old.deleted_at is not null and (new.deleted_at is distinct from old.deleted_at or new.is_active) then
   raise exception 'Deleted accounts cannot be restored' using errcode='42501';
  end if;
  removing:=old.is_active and (not new.is_active or new.deleted_at is not null);
 else
  target:=old.user_id;
  removing:=old.role='admin' and old.is_active and
   (tg_op='DELETE' or new.role<>'admin' or not new.is_active or new.user_id<>old.user_id);
 end if;
 if removing and janitra_private.is_admin(target) and not exists(
  select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
  where p.id<>target and p.is_active and p.deleted_at is null and r.role='admin' and r.is_active
 ) then raise exception 'The last active Admin cannot be removed' using errcode='42501'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function janitra_private.protect_last_admin() from public,anon,authenticated,service_role;
create trigger protect_admin_role before update or delete on public.role_assignments
 for each row execute function janitra_private.protect_last_admin();
create trigger protect_admin_profile before update on public.profiles
 for each row execute function janitra_private.protect_last_admin();

create or replace function public.owner_account_access(p_actor uuid,p_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.actor_session_valid(p_actor,p_session) and janitra_private.is_admin(p_actor);
$$;

create or replace function public.create_manpower_agency(p_actor uuid,p_name text,p_session uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare agency uuid;
begin
 if not public.owner_account_access(p_actor,p_session) or p_name is null or length(btrim(p_name)) not between 1 and 200 then
  raise exception 'Admin authority required' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.agencies(name) values(btrim(p_name)) returning id into agency;
 return agency;
end $$;

create or replace function public.can_invite_user(p_actor uuid,p_agency uuid,p_site uuid,p_role text)
returns boolean language sql stable security definer set search_path='' as $$
 select p_role in ('supervisor','personnel') and (p_role='supervisor' or p_site is not null)
  and exists(select 1 from public.agencies where id=p_agency)
  and (p_site is null or exists(select 1 from public.sites where id=p_site and agency_id=p_agency))
  and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
  and (p_role='personnel' or janitra_private.is_admin(p_actor));
$$;

create or replace function public.finish_user_invite(p_actor uuid,p_target uuid,p_email text,
 p_agency uuid,p_site uuid,p_role text,p_name text) returns text
language plpgsql security definer set search_path='' as $$
declare existing public.role_assignments%rowtype;
begin
 perform 1 from public.profiles where id in(p_actor,p_target) order by id for update;
 if not public.can_invite_user(p_actor,p_agency,p_site,p_role)
  or p_name is null or length(btrim(p_name)) not between 1 and 200
  or not exists(select 1 from auth.users where id=p_target and lower(email)=lower(btrim(p_email)))
  or exists(select 1 from public.profiles where id=p_target and (not is_active or deleted_at is not null))
  or exists(select 1 from public.role_assignments where user_id=p_target and role='admin')
  or (p_role='personnel' and exists(select 1 from public.role_assignments where user_id=p_target and role='supervisor'))
  or (p_role='supervisor' and exists(select 1 from public.role_assignments where user_id=p_target and role='personnel'))
 then raise exception 'Invitation not authorized for this account' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.profiles(id,full_name) values(p_target,btrim(p_name)) on conflict(id) do nothing;
 select * into existing from public.role_assignments where user_id=p_target and agency_id=p_agency
  and site_id is not distinct from p_site for update;
 if found then
  if existing.role<>p_role then raise exception 'Account has another role' using errcode='42501'; end if;
  return case when existing.is_active then 'already_assigned' else 'suspended' end;
 end if;
 insert into public.role_assignments(user_id,agency_id,site_id,role) values(p_target,p_agency,p_site,p_role);
 if p_role='personnel' then
  insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on) values(p_target,p_agency,p_site,current_date);
 end if;
 return 'assigned';
end $$;

create function public.finish_supervisor_invite(p_actor uuid,p_session uuid,p_target uuid,p_email text,
 p_agency uuid,p_sites uuid[],p_name text) returns text
language plpgsql security definer set search_path='' as $$
declare site uuid; result text;
begin
 if not public.owner_account_access(p_actor,p_session) or (p_sites is not null and
  (cardinality(p_sites)=0 or array_position(p_sites,null) is not null)) then
  raise exception 'Admin authority and valid Supervisor scope required' using errcode='42501'; end if;
 foreach site in array coalesce(p_sites,array[null::uuid]) loop
  result:=public.finish_user_invite(p_actor,p_target,p_email,p_agency,site,'supervisor',p_name);
 end loop;
 return result;
end $$;
revoke all on function public.finish_supervisor_invite(uuid,uuid,uuid,text,uuid,uuid[],text) from public,anon,authenticated;
grant execute on function public.finish_supervisor_invite(uuid,uuid,uuid,text,uuid,uuid[],text) to service_role;

create function public.can_delete_account(p_actor uuid,p_session uuid,p_target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.actor_session_valid(p_actor,p_session) and p_actor<>p_target
 and exists(select 1 from public.profiles where id=p_target and deleted_at is null)
 and not exists(select 1 from public.role_assignments where user_id=p_target and role='admin')
 and (janitra_private.is_admin(p_actor) or (
  exists(select 1 from public.role_assignments where user_id=p_target and role='personnel')
  and not exists(select 1 from public.role_assignments where user_id=p_target and
   (role<>'personnel' or not janitra_private.manager_has_scope(p_actor,agency_id,site_id)))));
$$;
revoke all on function public.can_delete_account(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.can_delete_account(uuid,uuid,uuid) to service_role;

create function public.edit_personnel(p_actor uuid,p_session uuid,p_target uuid,p_name text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.profiles where id in(p_actor,p_target) order by id for update;
 if not public.can_delete_account(p_actor,p_session,p_target)
  or exists(select 1 from public.role_assignments where user_id=p_target and role<>'personnel')
  or p_name is null or length(btrim(p_name)) not between 1 and 200 then
  raise exception 'Personnel editing not authorized' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 update public.profiles set full_name=btrim(p_name) where id=p_target;
 update janitra_private.personnel_identities set full_name=btrim(p_name) where user_id=p_target;
 return true;
end $$;
revoke all on function public.edit_personnel(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.edit_personnel(uuid,uuid,uuid,text) to service_role;

create or replace function public.owner_prepare_account_deletion(p_actor uuid,p_session uuid,p_target uuid,p_confirmation text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('erase/'||p_target::text,0));
 perform 1 from public.profiles where id in(p_actor,p_target) order by id for update;
 if p_confirmation is distinct from 'DELETE' or not public.can_delete_account(p_actor,p_session,p_target) then
  raise exception 'Account deletion not authorized' using errcode='42501'; end if;
 insert into janitra_private.account_deletions(target_id,owner_id,session_id,expires_at)
 values(p_target,p_actor,p_session,clock_timestamp()+interval '2 minutes')
 on conflict(target_id) do update set owner_id=excluded.owner_id,session_id=excluded.session_id,expires_at=excluded.expires_at,running_xid=null;
 return true;
end $$;

create or replace function janitra_private.erase_deleted_auth_account() returns trigger
language plpgsql security definer set search_path='' as $$
declare approval janitra_private.account_deletions%rowtype;
begin
 if not exists(select 1 from public.profiles where id=old.id) then return old; end if;
 perform pg_advisory_xact_lock(hashtextextended('erase/'||old.id::text,0));
 select * into approval from janitra_private.account_deletions where target_id=old.id for update;
 perform 1 from public.profiles where id in(old.id,approval.owner_id) order by id for update;
 perform 1 from auth.sessions where id=approval.session_id and user_id=approval.owner_id for share;
 perform 1 from public.role_assignments where user_id in(old.id,approval.owner_id) order by id for update;
 if approval.target_id is null or approval.expires_at<=clock_timestamp()
  or not public.can_delete_account(approval.owner_id,approval.session_id,old.id) then
  raise exception 'Current deletion authorization required' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',approval.owner_id,'role','authenticated','is_anonymous',false)::text,true);
 update public.profiles set is_active=false,deleted_at=clock_timestamp(),full_name='Deleted account' where id=old.id;
 update public.role_assignments set is_active=false where user_id=old.id;
 update public.personnel_assignments set is_active=false where user_id=old.id;
 delete from janitra_private.account_setup_grants where user_id=old.id;
 delete from janitra_private.identity_revoked_sessions where user_id=old.id;
 delete from janitra_private.personnel_identities where user_id=old.id;
 delete from janitra_private.employee_pin_credentials where user_id=old.id;
 delete from janitra_private.supervisor_pin_credentials where user_id=old.id;
 delete from auth.sessions where user_id=old.id;
 delete from janitra_private.supervisor_bootstrap_grants where user_id=old.id;
 delete from janitra_private.account_deletions where target_id=old.id;
 return old;
end $$;
create or replace function janitra_private.immutable_account_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'Account security history is immutable' using errcode='42501'; end $$;

create or replace function public.owner_list_accounts(p_actor uuid,p_session uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Session expired' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'user_id',p.id,'full_name',p.full_name,'email',case when i.username is null then u.email else coalesce(i.contact_email,'') end,
  'username',i.username,'role',r.role,'site_id',r.site_id,'agency_id',r.agency_id,
  'site_name',s.name,'agency_name',a.name,'is_active',p.is_active and r.is_active,'account_active',p.is_active,
  'is_transferred',r.ended_by_transfer is not null,'account_status',coalesce(i.state,case when p.is_active then 'active' else 'suspended' end),
  'can_delete',public.can_delete_account(p_actor,p_session,p.id)
 ) order by p.full_name,p.id,r.id) from public.profiles p join auth.users u on u.id=p.id
 join public.role_assignments r on r.user_id=p.id left join public.sites s on s.id=r.site_id
 left join public.agencies a on a.id=r.agency_id left join janitra_private.personnel_identities i on i.user_id=p.id
 where p.deleted_at is null and r.role<>'admin'
 and not exists(select 1 from public.role_assignments ar where ar.user_id=p.id and ar.role='admin')
 and (janitra_private.is_admin(p_actor) or (janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id)
  and (r.role='supervisor' or not exists(select 1 from public.role_assignments sr where sr.user_id=p.id and sr.role='supervisor'))))),'[]'::jsonb);
end $$;

create function public.manage_supervisor(p_actor uuid,p_session uuid,p_target uuid,p_agency uuid,
 p_sites uuid[],p_active boolean,p_name text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.profiles where id in(p_actor,p_target) order by id for update;
 perform 1 from public.role_assignments where user_id in(p_actor,p_target) order by id for update;
 if not public.owner_account_access(p_actor,p_session) or p_actor=p_target
  or p_active is null or p_name is null or length(btrim(p_name)) not between 1 and 200
  or not exists(select 1 from public.agencies where id=p_agency)
  or not exists(select 1 from public.profiles where id=p_target and deleted_at is null)
  or not exists(select 1 from public.role_assignments where user_id=p_target and role='supervisor')
  or exists(select 1 from public.role_assignments where user_id=p_target and role<>'supervisor')
  or (p_sites is not null and (cardinality(p_sites)=0 or array_position(p_sites,null) is not null
    or exists(select 1 from unnest(p_sites) x where not exists(select 1 from public.sites where id=x and agency_id=p_agency))))
 then raise exception 'Supervisor management not authorized' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 update public.profiles set full_name=btrim(p_name),is_active=p_active where id=p_target;
 update public.role_assignments set is_active=false where user_id=p_target and role='supervisor';
 insert into public.role_assignments(user_id,agency_id,site_id,role,is_active)
 select p_target,p_agency,x,'supervisor',p_active from unnest(coalesce(p_sites,array[null::uuid])) x
 on conflict(user_id,agency_id,site_id) do update set is_active=excluded.is_active;
 delete from auth.sessions where user_id=p_target;
 insert into public.audit_events(actor_id,agency_id,entity_type,entity_id,action,after_data)
 values(p_actor,p_agency,'supervisor_access',p_target,'update',jsonb_build_object('sites',p_sites,'active',p_active));
 return true;
end $$;
revoke all on function public.manage_supervisor(uuid,uuid,uuid,uuid,uuid[],boolean,text) from public,anon,authenticated;
grant execute on function public.manage_supervisor(uuid,uuid,uuid,uuid,uuid[],boolean,text) to service_role;

-- Reject cross-role targets even when a legacy Personnel assignment also exists.
alter function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) rename to set_personnel_access_scoped;
revoke all on function public.set_personnel_access_scoped(uuid,uuid,uuid,uuid,boolean) from service_role;
create function public.set_personnel_access(p_actor uuid,p_target uuid,p_agency uuid,p_site uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.profiles where id=p_target for update;
 if exists(select 1 from public.role_assignments where user_id=p_target and role in('admin','supervisor')) then
  raise exception 'Personnel management only' using errcode='42501'; end if;
 perform public.set_personnel_access_scoped(p_actor,p_target,p_agency,p_site,p_active);
end $$;
revoke all on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) to service_role;

alter function public.transfer_personnel_agency(uuid,uuid,uuid,uuid,uuid,text,uuid) rename to transfer_personnel_agency_scoped;
revoke all on function public.transfer_personnel_agency_scoped(uuid,uuid,uuid,uuid,uuid,text,uuid) from service_role;
create function public.transfer_personnel_agency(p_actor uuid,p_user uuid,p_from uuid,p_to uuid,p_site uuid,p_reason text,p_session uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.profiles where id=p_user for update;
 if exists(select 1 from public.role_assignments where user_id=p_user and role in('admin','supervisor')) then
  raise exception 'Personnel management only' using errcode='42501'; end if;
 return public.transfer_personnel_agency_scoped(p_actor,p_user,p_from,p_to,p_site,p_reason,p_session);
end $$;
revoke all on function public.transfer_personnel_agency(uuid,uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.transfer_personnel_agency(uuid,uuid,uuid,uuid,uuid,text,uuid) to service_role;

alter function public.personnel_identity_command(uuid,uuid,text,jsonb) rename to personnel_identity_command_scoped;
revoke all on function public.personnel_identity_command_scoped(uuid,uuid,text,jsonb) from service_role;
create function public.personnel_identity_command(p_actor uuid,p_session uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if p_action in ('issue_grant','finish_provision') then target:=(p_data->>'user_id')::uuid;
 elsif p_action='claim_grant' then
  select user_id into target from janitra_private.account_setup_grants where digest=p_data->>'digest';
 elsif p_action in ('finish_grant','reject_grant') then
  select user_id into target from janitra_private.account_setup_grants where claim_id=(p_data->>'claim_id')::uuid;
 end if;
 if target is not null then
  perform pg_advisory_xact_lock(hashtextextended('identity/'||target::text,0));
  perform 1 from public.profiles where id=target for update;
  if exists(select 1 from public.role_assignments where user_id=target and role in('admin','supervisor')) then
   if p_action='claim_grant' then return '{}'::jsonb; end if;
   raise exception 'Personnel recovery cannot change privileged accounts' using errcode='42501';
  end if;
 end if;
 return public.personnel_identity_command_scoped(p_actor,p_session,p_action,p_data);
end $$;
revoke all on function public.personnel_identity_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.personnel_identity_command(uuid,uuid,text,jsonb) to service_role;

alter function janitra_private.pin_scope(uuid,uuid,text,uuid,uuid,boolean) rename to pin_scope_scoped;
create function janitra_private.pin_scope(p_actor uuid,p_target uuid,p_kind text,p_agency uuid,p_site uuid,p_reset boolean)
returns boolean language sql stable security definer set search_path='' as $$
 select (p_kind='supervisor' and p_actor=p_target and janitra_private.is_admin(p_actor)
  and exists(select 1 from public.agencies where id=p_agency)
  and (p_site is null or exists(select 1 from public.sites where id=p_site and agency_id=p_agency)))
 or (not exists(select 1 from public.role_assignments where user_id=p_target and role in('admin','supervisor') and p_kind='employee')
  and janitra_private.pin_scope_scoped(p_actor,p_target,p_kind,p_agency,p_site,p_reset));
$$;
revoke all on function janitra_private.pin_scope(uuid,uuid,text,uuid,uuid,boolean) from public,anon,authenticated,service_role;

create or replace function janitra_private.verify_pin(p_user uuid,p_kind text,p_agency uuid,p_site uuid,p_digest text)
returns text language plpgsql security definer set search_path='' as $$
declare credential_table text; stored_hash text; attempts integer; locked timestamptz; now_at timestamptz;
begin
 if p_digest is null or p_digest !~ '^[0-9a-f]{64}$'
  or p_kind is null or p_kind not in ('employee','supervisor')
  or (p_site is not null and not exists(select 1 from public.sites where id=p_site and agency_id=p_agency))
  or not exists(select 1 from public.profiles where id=p_user and is_active and deleted_at is null)
  or not ((p_kind='supervisor' and janitra_private.is_admin(p_user)) or exists(
   select 1 from public.role_assignments where user_id=p_user and agency_id=p_agency and is_active
    and role=case p_kind when 'employee' then 'personnel' else 'supervisor' end
    and (site_id=p_site or (p_kind='supervisor' and site_id is null)))) then return 'denied'; end if;
 credential_table:=case p_kind when 'employee' then 'employee_pin_credentials' else 'supervisor_pin_credentials' end;
 execute format('select pin_hash,failed_attempts,locked_until from janitra_private.%I where user_id=$1 for update',credential_table)
  into stored_hash,attempts,locked using p_user;
 if stored_hash is null then return 'not_configured'; end if;
 now_at:=clock_timestamp();
 if locked is not null and locked>now_at then return 'locked'; end if;
 if locked is not null then attempts:=0; end if;
 if extensions.crypt(p_digest,stored_hash)=stored_hash then
  execute format('update janitra_private.%I set failed_attempts=0,locked_until=null where user_id=$1',credential_table) using p_user;
  return 'verified';
 end if;
 attempts:=attempts+1;
 execute format('update janitra_private.%I set failed_attempts=$2,locked_until=$3 where user_id=$1',credential_table)
  using p_user,attempts,case when attempts>=5 then now_at+interval '15 minutes' else null end;
 return case when attempts>=5 then 'locked' else 'incorrect' end;
end $$;

commit;
