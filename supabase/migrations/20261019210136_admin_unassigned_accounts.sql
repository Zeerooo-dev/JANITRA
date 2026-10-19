begin;

-- Unassigned roles never authorize a workspace, including Company-Wide access.
alter table public.role_assignments drop constraint role_assignments_scope_check;
alter table public.role_assignments add constraint role_assignments_scope_check check(
 (role='admin' and agency_id is null and site_id is null)
 or (role<>'admin' and agency_id is null and site_id is null and not is_active)
 or (role<>'admin' and agency_id is not null and (role='supervisor' or site_id is not null))
);
alter table janitra_private.personnel_identities alter column agency_id drop not null, alter column site_id drop not null;
alter table janitra_private.account_setup_grants alter column agency_id drop not null, alter column site_id drop not null;
alter table public.account_security_events alter column agency_id drop not null, alter column site_id drop not null;
alter table janitra_private.personnel_identities add constraint identity_scope_pair check((agency_id is null)=(site_id is null));
alter table janitra_private.account_setup_grants add constraint grant_scope_pair check((agency_id is null)=(site_id is null));
alter table public.account_security_events add constraint security_scope_pair check((agency_id is null)=(site_id is null));

create or replace function public.can_invite_user(p_actor uuid,p_agency uuid,p_site uuid,p_role text)
returns boolean language sql stable security definer set search_path='' as $$
 select p_role in ('supervisor','personnel') and
 ((p_agency is null and p_site is null and janitra_private.is_admin(p_actor)) or
  (p_agency is not null and (p_role='supervisor' or p_site is not null)
   and exists(select 1 from public.agencies where id=p_agency)
   and (p_site is null or exists(select 1 from public.sites where id=p_site and agency_id=p_agency))
   and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
   and (p_role='personnel' or janitra_private.is_admin(p_actor))));
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
  or exists(select 1 from public.role_assignments where user_id=p_target and role<>p_role)
  or (p_agency is null and exists(select 1 from public.role_assignments where user_id=p_target and agency_id is not null))
 then raise exception 'Invitation not authorized' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.profiles(id,full_name) values(p_target,btrim(p_name)) on conflict(id) do nothing;
 select * into existing from public.role_assignments where user_id=p_target
  and agency_id is not distinct from p_agency and site_id is not distinct from p_site;
 if found then
  if p_agency is null then return 'unassigned'; end if;
  return case when existing.is_active then 'already_assigned' else 'suspended' end;
 end if;
 insert into public.role_assignments(user_id,agency_id,site_id,role,is_active)
 values(p_target,p_agency,p_site,p_role,p_agency is not null);
 if p_role='personnel' and p_site is not null then
  insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on) values(p_target,p_agency,p_site,current_date);
 end if;
 if p_agency is not null then
  delete from public.role_assignments where user_id=p_target and agency_id is null and role<>'admin' and not is_active;
 end if;
 return case when p_agency is null then 'unassigned' else 'assigned' end;
end $$;

-- Extend the existing provisioning/grant implementation, preserving its locks,
-- grant expiry, recovery safeguards and immutable security events.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.personnel_identity_command_scoped(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(definition,'i.agency_id<>agency')=0 or strpos(definition,'not exists(select 1 from public.sites where id=site and agency_id=agency)')=0 then
  raise exception 'Unexpected identity implementation'; end if;
 definition:=replace(definition,'i.agency_id<>agency','i.agency_id is distinct from agency');
 definition:=replace(definition,'i.site_id<>site','i.site_id is distinct from site');
 definition:=replace(definition,'role=''supervisor'' and is_active for share',
  'role in (''supervisor'',''admin'') and is_active for share');
 definition:=replace(definition,
  'not exists(select 1 from public.sites where id=site and agency_id=agency)',
  'not ((agency is null and site is null and janitra_private.is_admin(p_actor)) or exists(select 1 from public.sites where id=site and agency_id=agency))');
 definition:=replace(definition,
  'r.role=''personnel'' and r.agency_id=agency and r.site_id=site)',
  'r.role=''personnel'' and r.agency_id is not distinct from agency and r.site_id is not distinct from site)');
 definition:=replace(definition,
  'insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on,is_active) values(target,agency,site,(clock_timestamp() at time zone ''Asia/Manila'')::date,false) on conflict(user_id,site_id,starts_on) do nothing;',
  'if site is not null then insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on,is_active) values(target,agency,site,(clock_timestamp() at time zone ''Asia/Manila'')::date,false) on conflict(user_id,site_id,starts_on) do nothing; end if;');
 definition:=replace(definition,
  'r.is_active and r.role=''personnel''',
  '(r.is_active or (r.agency_id is null and r.site_id is null)) and r.role=''personnel''');
 execute definition;

 definition:=pg_get_functiondef('public.owner_list_accounts(uuid,uuid)'::regprocedure);
 definition:=replace(definition,'''role'',r.role,','''is_unassigned'',r.agency_id is null,''role'',r.role,');
 -- Unassigned identities are visible only to Admin, never company directories.
 definition:=replace(definition,'where p.deleted_at is null and r.role<>''admin''',
  'where p.deleted_at is null and (r.agency_id is not null or janitra_private.is_admin(p_actor)) and r.role<>''admin''');
 execute definition;

 definition:=pg_get_functiondef('public.manage_supervisor(uuid,uuid,uuid,uuid,uuid[],boolean,text)'::regprocedure);
 definition:=replace(definition,'delete from auth.sessions where user_id=p_target;',
  'delete from public.role_assignments where user_id=p_target and agency_id is null and role=''supervisor'' and not is_active; delete from auth.sessions where user_id=p_target;');
 execute definition;
end $$;

create function public.assign_unassigned_personnel(p_actor uuid,p_session uuid,p_target uuid,p_agency uuid,p_site uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare enabled boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('identity/'||p_target::text,0));
 perform 1 from public.profiles where id in(p_actor,p_target) order by id for update;
 if not public.owner_account_access(p_actor,p_session) or p_actor=p_target
  or not exists(select 1 from public.sites where id=p_site and agency_id=p_agency)
  or not exists(select 1 from public.profiles where id=p_target and deleted_at is null)
  or not exists(select 1 from public.role_assignments where user_id=p_target and role='personnel' and agency_id is null and site_id is null and not is_active)
  or exists(select 1 from public.role_assignments where user_id=p_target and (role<>'personnel' or agency_id is not null))
  or exists(select 1 from janitra_private.account_setup_grants where user_id=p_target and state='claimed')
 then raise exception 'Unassigned Personnel management not authorized' using errcode='42501'; end if;
 select p.is_active and coalesce(i.state='active',true) into enabled from public.profiles p
 left join janitra_private.personnel_identities i on i.user_id=p.id where p.id=p_target;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 update public.role_assignments set agency_id=p_agency,site_id=p_site,is_active=enabled where user_id=p_target and agency_id is null;
 insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on,is_active) values(p_target,p_agency,p_site,current_date,enabled);
 update janitra_private.personnel_identities set agency_id=p_agency,site_id=p_site where user_id=p_target;
 update janitra_private.account_setup_grants set agency_id=p_agency,site_id=p_site where user_id=p_target and state='issued';
 insert into public.audit_events(actor_id,agency_id,site_id,entity_type,entity_id,action,after_data)
 values(p_actor,p_agency,p_site,'personnel_assignment',p_target,'update',jsonb_build_object('active',enabled));
 return true;
end $$;
revoke all on function public.assign_unassigned_personnel(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_unassigned_personnel(uuid,uuid,uuid,uuid,uuid) to service_role;

create or replace function public.actor_session_state(p_actor uuid,p_session uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when not exists(select 1 from public.profiles where id=p_actor and is_active and deleted_at is null) then 'suspended'
  when not exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()))
   or exists(select 1 from janitra_private.identity_revoked_sessions where session_id=p_session) then 'expired'
  when exists(select 1 from public.role_assignments where user_id=p_actor and is_active) then 'active'
  when exists(select 1 from public.role_assignments where user_id=p_actor and agency_id is null and role<>'admin' and not is_active) then 'unassigned'
  else 'revoked' end;
$$;

create or replace function public.needs_password_setup() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and janitra_private.live_auth_session()
  and exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and coalesce(encrypted_password,'')='')
  and exists(select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
   where p.id=auth.uid() and p.is_active and p.deleted_at is null
    and (r.is_active or (r.agency_id is null and not r.is_active)));
$$;
commit;
