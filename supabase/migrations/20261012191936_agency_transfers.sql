begin;

create table public.agency_transfers (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 actor_id uuid not null references public.profiles(id),
 agency_id uuid not null references public.agencies(id),
 destination_agency_id uuid not null references public.agencies(id),
 site_id uuid not null,
 source_name text not null, destination_name text not null, workplace_name text not null,
 reason text not null check(length(btrim(reason)) between 1 and 2000),
 occurred_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,destination_agency_id) references public.sites(id,agency_id)
);
alter table public.agency_transfers enable row level security;
alter table public.role_assignments add column ended_by_transfer uuid references public.agency_transfers(id);
create index roles_transfer_idx on public.role_assignments(ended_by_transfer) where ended_by_transfer is not null;
revoke all on public.agency_transfers from public,anon,authenticated,service_role;
grant select on public.agency_transfers to authenticated;
create policy transfer_history on public.agency_transfers for select to authenticated using (
 janitra_private.has_site_role(agency_id,null,array['supervisor'])
 or janitra_private.has_site_role(destination_agency_id,site_id,array['supervisor'])
 or (user_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and is_active))
);
create index agency_transfers_user_idx on public.agency_transfers(user_id,occurred_at desc);

create function public.create_manpower_agency(p_actor uuid,p_name text,p_session uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare agency uuid;
begin
 perform 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_actor and is_active for share;
 perform 1 from public.role_assignments where user_id=p_actor and role='supervisor' and is_active and site_id is null order by id for share;
 if p_name is null or length(btrim(p_name)) not between 1 and 200
  or not exists(select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
    where p.id=p_actor and p.is_active and r.role='supervisor' and r.is_active and r.site_id is null)
 then raise exception 'Agency creation not authorized' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.agencies(name) values(btrim(p_name)) returning id into agency;
 insert into public.role_assignments(user_id,agency_id,role) values(p_actor,agency,'supervisor');
 return agency;
end; $$;
revoke all on function public.create_manpower_agency(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.create_manpower_agency(uuid,text,uuid) to service_role;

create function public.transfer_personnel_agency(p_actor uuid,p_user uuid,p_from uuid,p_to uuid,p_site uuid,p_reason text,p_session uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare today date := (clock_timestamp() at time zone 'Asia/Manila')::date; destination public.role_assignments%rowtype; transfer_id uuid:=gen_random_uuid();
begin
 perform 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'Session expired' using errcode='42501'; end if;
 if p_from=p_to then raise exception 'Choose a different destination agency'; end if;
 perform 1 from public.profiles where id=p_actor and is_active for share;
 perform 1 from public.role_assignments where user_id=p_actor and role='supervisor' and is_active and site_id is null and agency_id in(p_from,p_to) order by id for share;
 if p_actor=p_user or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
  or not janitra_private.manager_has_scope(p_actor,p_from,null)
  or not janitra_private.manager_has_scope(p_actor,p_to,null)
  or not exists(select 1 from public.sites where id=p_site and agency_id=p_to)
 then raise exception 'Transfer requires authority over both agencies' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_user and is_active for update;
 if not found then raise exception 'Personnel unavailable' using errcode='42501'; end if;
 perform 1 from public.role_assignments where user_id=p_user and agency_id in (p_from,p_to) order by id for update;
 if not exists(select 1 from public.role_assignments where user_id=p_user and agency_id=p_from and role='personnel' and is_active)
 then raise exception 'Source assignment unavailable' using errcode='42501'; end if;
 select * into destination from public.role_assignments where user_id=p_user and agency_id=p_to and site_id=p_site;
 if found and destination.role<>'personnel' then raise exception 'Destination has a different role' using errcode='23505'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.agency_transfers(id,user_id,actor_id,agency_id,destination_agency_id,site_id,reason,source_name,destination_name,workplace_name)
  values(transfer_id,p_user,p_actor,p_from,p_to,p_site,btrim(p_reason),(select name from public.agencies where id=p_from),(select name from public.agencies where id=p_to),(select name from public.sites where id=p_site));
 update public.role_assignments set is_active=false,ended_by_transfer=transfer_id where user_id=p_user and agency_id=p_from and role='personnel' and is_active;
 update public.personnel_assignments set is_active=false,ends_on=greatest(starts_on,today)
  where user_id=p_user and agency_id=p_from and is_active;
 insert into public.role_assignments(user_id,agency_id,site_id,role,is_active) values(p_user,p_to,p_site,'personnel',true)
  on conflict(user_id,agency_id,site_id) do update set is_active=true,ended_by_transfer=null;
 insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on,is_active) values(p_user,p_to,p_site,today,true)
  on conflict(user_id,site_id,starts_on) do update set is_active=true,ends_on=null;
 return jsonb_build_object('transferred',true);
end; $$;
revoke all on function public.transfer_personnel_agency(uuid,uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.transfer_personnel_agency(uuid,uuid,uuid,uuid,uuid,text,uuid) to service_role;

drop function public.list_managed_users(uuid,uuid);
create function public.list_managed_users(p_actor uuid,p_agency uuid)
returns table(user_id uuid,email text,full_name text,role text,site_id uuid,is_active boolean,is_transferred boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
  where r.user_id=p_actor and r.agency_id=p_agency and r.role='supervisor' and r.is_active and p.is_active)
 then raise exception 'User list not authorized' using errcode='42501'; end if;
 return query select r.user_id,u.email::text,p.full_name,r.role,r.site_id,r.is_active,r.ended_by_transfer is not null
  from public.role_assignments r join public.profiles p on p.id=r.user_id join auth.users u on u.id=r.user_id
  where r.agency_id=p_agency and ((r.role='personnel' and janitra_private.manager_has_scope(p_actor,p_agency,r.site_id))
   or (r.role='supervisor' and janitra_private.manager_has_scope(p_actor,p_agency,null))) order by p.full_name,r.site_id;
end; $$;
revoke all on function public.list_managed_users(uuid,uuid) from public,anon,authenticated;
grant execute on function public.list_managed_users(uuid,uuid) to service_role;

create or replace function public.set_personnel_access(p_actor uuid,p_target uuid,p_agency uuid,p_site uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_actor=p_target or p_active is null or p_site is null or not janitra_private.manager_has_scope(p_actor,p_agency,p_site)
  or not exists(select 1 from public.role_assignments where user_id=p_target and agency_id=p_agency and site_id=p_site and role='personnel' and ended_by_transfer is null)
 then raise exception 'Transferred Personnel cannot be reactivated in an old agency' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 update public.role_assignments set is_active=p_active where user_id=p_target and agency_id=p_agency and site_id=p_site and role='personnel' and is_active is distinct from p_active;
 update public.personnel_assignments set is_active=p_active where user_id=p_target and agency_id=p_agency and site_id=p_site and starts_on<=current_date and (ends_on is null or ends_on>=current_date) and is_active is distinct from p_active;
end; $$;
commit;
