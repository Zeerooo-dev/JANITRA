begin;

-- Every public entry point is service-only. The Edge Function authenticates the
-- user and passes its verified ID; these checks repeat authorization in Postgres.
create function janitra_private.manager_has_scope(p_actor uuid, p_agency uuid, p_site uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
    where p.id=p_actor and p.is_active and r.is_active and r.role='supervisor'
      and r.agency_id=p_agency and (r.site_id is null or r.site_id=p_site)
  );
$$;
revoke all on function janitra_private.manager_has_scope(uuid,uuid,uuid) from public, anon, authenticated, service_role;

create function public.can_invite_user(p_actor uuid, p_agency uuid, p_site uuid, p_role text)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_role in ('supervisor','personnel')
    and (p_role='personnel' or p_site is null)
    and (p_role='supervisor' or p_site is not null)
    and (p_site is null or exists(select 1 from public.sites s where s.id=p_site and s.agency_id=p_agency))
    and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
    and (p_role<>'supervisor' or janitra_private.manager_has_scope(p_actor,p_agency,null));
$$;
revoke all on function public.can_invite_user(uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.can_invite_user(uuid,uuid,uuid,text) to service_role;

create function public.find_invite_target(p_actor uuid, p_agency uuid, p_site uuid, p_role text, p_email text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare target uuid;
begin
  if not public.can_invite_user(p_actor,p_agency,p_site,p_role) then
    raise exception 'User invitation not authorized' using errcode='42501';
  end if;
  select u.id into target from auth.users u where lower(u.email)=lower(btrim(p_email)) limit 1;
  return target;
end;
$$;
revoke all on function public.find_invite_target(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.find_invite_target(uuid,uuid,uuid,text,text) to service_role;

create function public.finish_user_invite(p_actor uuid, p_target uuid, p_email text,
  p_agency uuid, p_site uuid, p_role text, p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare existing public.role_assignments%rowtype;
begin
  if not public.can_invite_user(p_actor,p_agency,p_site,p_role)
    or p_name is null or length(btrim(p_name)) not between 1 and 200
    or p_email is null or length(btrim(p_email)) not between 3 and 320
    or not exists(select 1 from auth.users u where u.id=p_target and lower(u.email)=lower(btrim(p_email))) then
    raise exception 'Invalid or unauthorized invitation' using errcode='42501';
  end if;
  if exists(select 1 from public.profiles p where p.id=p_target and not p.is_active) then
    raise exception 'Account is suspended' using errcode='42501';
  end if;
  -- The audit trigger derives its actor from auth.uid(). The Edge Function is
  -- the only caller, and this setting lasts only for this request transaction.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
  insert into public.profiles(id,full_name) values(p_target,btrim(p_name)) on conflict(id) do nothing;
  select * into existing from public.role_assignments r
    where r.user_id=p_target and r.agency_id=p_agency and r.site_id is not distinct from p_site for update;
  if found then
    if existing.role<>p_role then raise exception 'Account has another role at this site' using errcode='23505'; end if;
    return case when existing.is_active then 'already_assigned' else 'suspended' end;
  end if;
  insert into public.role_assignments(user_id,agency_id,site_id,role)
    values(p_target,p_agency,p_site,p_role);
  if p_role='personnel' then
    insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on)
      values(p_target,p_agency,p_site,current_date);
  end if;
  return 'assigned';
end;
$$;
revoke all on function public.finish_user_invite(uuid,uuid,text,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.finish_user_invite(uuid,uuid,text,uuid,uuid,text,text) to service_role;

create function public.list_managed_users(p_actor uuid, p_agency uuid)
returns table(user_id uuid, email text, full_name text, role text, site_id uuid, is_active boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not janitra_private.manager_has_scope(p_actor,p_agency,null)
    and not exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
      where r.user_id=p_actor and r.agency_id=p_agency and r.role='supervisor'
        and r.is_active and p.is_active) then
    raise exception 'User list not authorized' using errcode='42501';
  end if;
  return query select r.user_id, u.email::text, p.full_name, r.role, r.site_id, r.is_active
    from public.role_assignments r join public.profiles p on p.id=r.user_id
    join auth.users u on u.id=r.user_id
    where r.agency_id=p_agency and (
      (r.role='personnel' and janitra_private.manager_has_scope(p_actor,p_agency,r.site_id))
      or (r.role='supervisor' and janitra_private.manager_has_scope(p_actor,p_agency,null))
    ) order by p.full_name,r.site_id;
end;
$$;
revoke all on function public.list_managed_users(uuid,uuid) from public, anon, authenticated;
grant execute on function public.list_managed_users(uuid,uuid) to service_role;

create function public.set_personnel_access(p_actor uuid, p_target uuid, p_agency uuid,
  p_site uuid, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if p_active is null or p_site is null or p_actor=p_target
    or not janitra_private.manager_has_scope(p_actor,p_agency,p_site) then
    raise exception 'Personnel change not authorized' using errcode='42501';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
  update public.role_assignments r set is_active=p_active
    where r.user_id=p_target and r.agency_id=p_agency and r.site_id=p_site
      and r.role='personnel' and r.is_active is distinct from p_active;
  get diagnostics changed=row_count;
  if changed=0 and not exists(select 1 from public.role_assignments r
      where r.user_id=p_target and r.agency_id=p_agency and r.site_id=p_site and r.role='personnel'
        and r.is_active=p_active) then
    raise exception 'Personnel assignment not found' using errcode='42501';
  end if;
  update public.personnel_assignments pa set is_active=p_active
    where pa.user_id=p_target and pa.agency_id=p_agency and pa.site_id=p_site
      and pa.starts_on<=current_date and (pa.ends_on is null or pa.ends_on>=current_date)
      and pa.is_active is distinct from p_active;
end;
$$;
revoke all on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) to service_role;

-- Newly invited Personnel and Supervisors must choose a password after accepting
-- their email invitation, just like the first Supervisor.
create or replace function public.needs_password_setup() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false)=false
    and exists(select 1 from auth.users u where u.id=auth.uid()
      and u.email_confirmed_at is not null and coalesce(u.encrypted_password,'')='')
    and (public.needs_company_setup() or exists (
      select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
      where p.id=auth.uid() and p.is_active and r.is_active
    ));
$$;

commit;
