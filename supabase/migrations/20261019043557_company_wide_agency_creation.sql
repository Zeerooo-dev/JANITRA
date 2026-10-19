begin;

create or replace function public.create_manpower_agency(p_actor uuid,p_name text,p_session uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare agency uuid;
begin
 perform 1 from auth.sessions where id=p_session and user_id=p_actor
  and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_actor for share;
 perform 1 from public.role_assignments where user_id=p_actor and is_active
  and (role='admin' or (role='supervisor' and site_id is null)) order by id for share;
 if not found or not (janitra_private.is_admin(p_actor) or janitra_private.is_company_wide_supervisor(p_actor)) then
  raise exception 'Agency creation not authorized' using errcode='42501';
 end if;
 if not public.actor_session_valid(p_actor,p_session) then
  raise exception 'Session expired' using errcode='42501';
 end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 200 then
  raise exception 'Enter a manpower agency name of 1 to 200 characters' using errcode='22023';
 end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 insert into public.agencies(name) values(btrim(p_name)) returning id into agency;
 return agency;
end $$;
revoke all on function public.create_manpower_agency(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.create_manpower_agency(uuid,text,uuid) to service_role;

commit;
