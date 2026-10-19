begin;

create table janitra_private.supervisor_bootstrap_grants (
  user_id uuid primary key references auth.users(id) on delete restrict,
  agency_id uuid references public.agencies(id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check ((agency_id is null) = (completed_at is null))
);
alter table janitra_private.supervisor_bootstrap_grants enable row level security;
revoke all on janitra_private.supervisor_bootstrap_grants from public, anon, authenticated;
grant select, insert on janitra_private.supervisor_bootstrap_grants to service_role;

create function public.needs_company_setup() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
    and exists (
      select 1 from janitra_private.supervisor_bootstrap_grants g
      join auth.users u on u.id=g.user_id
      where g.user_id=auth.uid() and g.completed_at is null and u.email_confirmed_at is not null
    )
    and not exists(select 1 from public.profiles p where p.id=auth.uid() and not p.is_active);
$$;

create function public.needs_password_setup() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.needs_company_setup() and exists (
    select 1 from auth.users u where u.id=auth.uid() and coalesce(u.encrypted_password,'')=''
  );
$$;

create function public.setup_manpower_company(company_name text, supervisor_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid();
  bootstrap janitra_private.supervisor_bootstrap_grants%rowtype;
  new_agency uuid;
begin
  if caller is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
    or not exists(select 1 from auth.users u where u.id=caller and u.email_confirmed_at is not null
      and coalesce(u.encrypted_password,'')<>'')
    or exists(select 1 from public.profiles p where p.id=caller and not p.is_active) then
    raise exception 'Company setup is not authorized' using errcode='42501';
  end if;
  if company_name is null or length(btrim(company_name)) not between 1 and 200
    or supervisor_name is null or length(btrim(supervisor_name)) not between 1 and 200 then
    raise exception 'Company name and Supervisor name must contain 1 to 200 characters' using errcode='22023';
  end if;
  select * into bootstrap from janitra_private.supervisor_bootstrap_grants g
    where g.user_id=caller for update;
  if not found then raise exception 'Company setup is not authorized' using errcode='42501'; end if;
  if bootstrap.completed_at is not null then
    if not janitra_private.has_site_role(bootstrap.agency_id,null,array['supervisor']) then
      raise exception 'Company setup is not authorized' using errcode='42501';
    end if;
    return bootstrap.agency_id;
  end if;
  if exists(select 1 from public.role_assignments r where r.user_id=caller) then
    raise exception 'Account already has workplace access' using errcode='42501';
  end if;
  insert into public.profiles(id,full_name) values(caller,btrim(supervisor_name))
    on conflict(id) do update set full_name=excluded.full_name;
  insert into public.agencies(name) values(btrim(company_name)) returning id into new_agency;
  insert into public.role_assignments(user_id,agency_id,role) values(caller,new_agency,'supervisor');
  update janitra_private.supervisor_bootstrap_grants
    set agency_id=new_agency, completed_at=clock_timestamp() where user_id=caller;
  return new_agency;
end;
$$;

revoke all on function public.needs_company_setup(), public.needs_password_setup(), public.setup_manpower_company(text,text) from public, anon;
grant execute on function public.needs_company_setup(), public.needs_password_setup(), public.setup_manpower_company(text,text) to authenticated;

commit;
