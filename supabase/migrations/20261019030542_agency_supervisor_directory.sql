begin;

create or replace function public.owner_list_accounts(p_actor uuid,p_session uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare directory_access boolean;
begin
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Session expired' using errcode='42501'; end if;
 select exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
  where r.user_id=p_actor and p.is_active and p.deleted_at is null and r.is_active
   and r.role='supervisor' and r.site_id is null) into directory_access;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'user_id',p.id,'full_name',p.full_name,
  'email',case when janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id)
   then case when i.username is null then u.email else coalesce(i.contact_email,'') end end,
  'username',case when janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id) then i.username end,
  'role',r.role,'site_id',r.site_id,'agency_id',r.agency_id,
  'site_name',s.name,'agency_name',a.name,'is_active',p.is_active and r.is_active,'account_active',p.is_active,
  'is_transferred',r.ended_by_transfer is not null,'account_status',coalesce(i.state,case when p.is_active then 'active' else 'suspended' end),
  'can_delete',public.can_delete_account(p_actor,p_session,p.id)
 ) order by p.full_name,p.id,r.id) from public.profiles p join auth.users u on u.id=p.id
 join public.role_assignments r on r.user_id=p.id left join public.sites s on s.id=r.site_id
 left join public.agencies a on a.id=r.agency_id left join janitra_private.personnel_identities i on i.user_id=p.id
 where p.deleted_at is null and r.role<>'admin'
 and not exists(select 1 from public.role_assignments ar where ar.user_id=p.id and ar.role='admin')
 and (janitra_private.is_admin(p_actor) or directory_access or (janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id)
  and (r.role='supervisor' or not exists(select 1 from public.role_assignments sr where sr.user_id=p.id and sr.role='supervisor'))))),'[]'::jsonb);
end $$;
revoke all on function public.owner_list_accounts(uuid,uuid) from public,anon,authenticated;
grant execute on function public.owner_list_accounts(uuid,uuid) to service_role;

commit;
