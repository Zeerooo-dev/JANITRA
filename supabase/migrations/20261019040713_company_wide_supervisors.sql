begin;

create function janitra_private.is_company_wide_supervisor(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
  where p.id=p_user and p.is_active and p.deleted_at is null and r.is_active
   and r.role='supervisor' and r.site_id is null);
$$;
revoke all on function janitra_private.is_company_wide_supervisor(uuid) from public,anon,authenticated,service_role;

create or replace function janitra_private.manager_has_scope(p_actor uuid,p_agency uuid,p_site uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.is_admin(p_actor) or
  (janitra_private.is_company_wide_supervisor(p_actor) and exists(select 1 from public.agencies where id=p_agency)
   and (p_site is null or exists(select 1 from public.sites where id=p_site and agency_id=p_agency))) or exists(
  select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
  where p.id=p_actor and p.is_active and p.deleted_at is null and r.is_active
   and r.role='supervisor' and r.agency_id=p_agency and r.site_id=p_site);
$$;

create or replace function janitra_private.has_site_role(target_agency uuid,target_site uuid,required_roles text[])
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and (janitra_private.is_admin(auth.uid())
   or (target_agency is not null and 'supervisor'=any(required_roles) and janitra_private.is_company_wide_supervisor(auth.uid()))
   or exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
    where r.user_id=auth.uid() and p.is_active and p.deleted_at is null and r.is_active
     and r.agency_id=target_agency and r.role=any(required_roles) and r.site_id=target_site));
$$;

create or replace function janitra_private.is_agency_member(target_agency uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and (janitra_private.is_admin(auth.uid()) or (target_agency is not null and janitra_private.is_company_wide_supervisor(auth.uid()))
   or exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
    where r.user_id=auth.uid() and p.is_active and p.deleted_at is null and r.is_active and r.agency_id=target_agency));
$$;

create or replace function janitra_private.pin_scope(p_actor uuid,p_target uuid,p_kind text,p_agency uuid,p_site uuid,p_reset boolean)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=p_actor and is_active and deleted_at is null)
  and exists(select 1 from public.profiles where id=p_target and is_active and deleted_at is null)
  and exists(select 1 from public.agencies where id=p_agency)
  and (p_site is null or exists(select 1 from public.sites where id=p_site and agency_id=p_agency))
  and case p_kind
   when 'supervisor' then p_actor=p_target and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
   when 'employee' then p_site is not null and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
    and not exists(select 1 from public.role_assignments where user_id=p_target and role in('admin','supervisor'))
    and exists(select 1 from public.role_assignments where user_id=p_target and agency_id=p_agency and site_id=p_site and role='personnel' and is_active)
    and (not p_reset or not exists(select 1 from public.role_assignments where user_id=p_target and role='personnel' and is_active
     and not janitra_private.manager_has_scope(p_actor,agency_id,site_id)))
   else false end;
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
   (r.role='admin' or (r.role='supervisor' and (r.site_id is null or (r.agency_id=t.agency_id and r.site_id=t.site_id))));
 elsif p_event<>'scheduled' then
  insert into public.task_notifications(task_id,recipient_id,agency_id,site_id,message)
  values(t.id,t.user_id,t.agency_id,t.site_id,t.personnel_name||': '||replace(p_event,'_',' ')||'.');
 end if;
end $$;

do $$
declare definition text; before_task text; before_scope text;
begin
 definition:=pg_get_functiondef('public.workflow_command_without_checklists(uuid,uuid,text,jsonb)'::regprocedure);
 before_task:='role=''supervisor'' and agency_id=t.agency_id and (site_id is null or site_id=t.site_id)';
 before_scope:='role=''supervisor'' and agency_id=agency and (site_id is null or site_id=site)';
 if strpos(definition,before_task)=0 or strpos(definition,before_scope)=0 then raise exception 'Unexpected workflow scope locks'; end if;
 definition:=replace(definition,before_task,'role=''supervisor'' and (site_id is null or (agency_id=t.agency_id and site_id=t.site_id))');
 definition:=replace(definition,before_scope,'role=''supervisor'' and (site_id is null or (agency_id=agency and site_id=site))');
 execute definition;

 definition:=pg_get_functiondef('public.workflow_command(uuid,uuid,text,jsonb)'::regprocedure);
 before_scope:=E'where user_id=p_actor and is_active and role=''supervisor''\n  and agency_id=agency and (site_id is null or site_id=site)';
 if strpos(definition,before_scope)=0 then raise exception 'Unexpected scheduling scope lock'; end if;
 execute replace(definition,before_scope,'where user_id=p_actor and is_active and (role=''admin'' or (role=''supervisor'' and (site_id is null or (agency_id=agency and site_id=site))))');

 definition:=pg_get_functiondef('janitra_private.verify_pin(uuid,text,uuid,uuid,text)'::regprocedure);
 before_scope:='(p_kind=''supervisor'' and janitra_private.is_admin(p_user))';
 if strpos(definition,before_scope)=0 then raise exception 'Unexpected Supervisor PIN scope'; end if;
 execute replace(definition,before_scope,'(p_kind=''supervisor'' and (janitra_private.is_admin(p_user) or janitra_private.is_company_wide_supervisor(p_user)))');

 definition:=pg_get_functiondef('public.transfer_personnel_agency_scoped(uuid,uuid,uuid,uuid,uuid,text,uuid)'::regprocedure);
 before_scope:='where user_id=p_actor and role=''supervisor'' and is_active and site_id is null and agency_id in(p_from,p_to)';
 if strpos(definition,before_scope)=0 then raise exception 'Unexpected transfer scope lock'; end if;
 execute replace(definition,before_scope,'where user_id=p_actor and is_active and (role=''admin'' or (role=''supervisor'' and site_id is null))');
end $$;

commit;
