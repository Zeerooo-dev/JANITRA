begin;
create table janitra_private.account_owners (
 user_id uuid primary key references public.profiles(id) on delete restrict,
 granted_at timestamptz not null default clock_timestamp()
);
create table janitra_private.account_deletions (
 target_id uuid primary key,
 owner_id uuid not null references public.profiles(id), session_id uuid not null,
 expires_at timestamptz not null, running_xid text
);
alter table janitra_private.account_owners enable row level security;
alter table janitra_private.account_deletions enable row level security;
revoke all on janitra_private.account_owners,janitra_private.account_deletions from public,anon,authenticated,service_role;

create function public.owner_account_access(p_actor uuid,p_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.actor_session_valid(p_actor,p_session) and exists(
  select 1 from janitra_private.account_owners where user_id=p_actor
 );
$$;
revoke all on function public.owner_account_access(uuid,uuid) from public,anon,authenticated;
grant execute on function public.owner_account_access(uuid,uuid) to service_role;

create function public.owner_list_accounts(p_actor uuid,p_session uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not public.owner_account_access(p_actor,p_session) then raise exception 'Owner access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'user_id',p.id,'full_name',p.full_name,'email',case when i.username is null then u.email else coalesce(i.contact_email,'') end,
  'username',i.username,'role',coalesce(r.role,'personnel'),'site_id',r.site_id,'agency_id',r.agency_id,
  'site_name',s.name,'agency_name',a.name,'is_active',p.is_active and coalesce(r.is_active,false),
  'is_transferred',r.ended_by_transfer is not null,'account_status',coalesce(i.state,case when p.is_active then 'active' else 'suspended' end),
  'can_delete',not exists(select 1 from janitra_private.account_owners o where o.user_id=p.id)
 ) order by p.full_name,p.id,r.id) from public.profiles p join auth.users u on u.id=p.id
 left join public.role_assignments r on r.user_id=p.id left join public.sites s on s.id=r.site_id
 left join public.agencies a on a.id=r.agency_id left join janitra_private.personnel_identities i on i.user_id=p.id),'[]'::jsonb);
end $$;
revoke all on function public.owner_list_accounts(uuid,uuid) from public,anon,authenticated;
grant execute on function public.owner_list_accounts(uuid,uuid) to service_role;

create function public.owner_prepare_account_deletion(p_actor uuid,p_session uuid,p_target uuid,p_confirmation text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('erase/'||p_target::text,0));
 if not public.owner_account_access(p_actor,p_session) or p_confirmation is distinct from 'DELETE'
  or p_target=p_actor or exists(select 1 from janitra_private.account_owners where user_id=p_target)
  or not exists(select 1 from public.profiles where id=p_target) then
  raise exception 'Account deletion not authorized' using errcode='42501';
 end if;
 insert into janitra_private.account_deletions(target_id,owner_id,session_id,expires_at)
  values(p_target,p_actor,p_session,clock_timestamp()+interval '2 minutes')
  on conflict(target_id) do update set owner_id=excluded.owner_id,session_id=excluded.session_id,
   expires_at=excluded.expires_at,running_xid=null;
 return true;
end $$;
revoke all on function public.owner_prepare_account_deletion(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.owner_prepare_account_deletion(uuid,uuid,uuid,text) to service_role;

create function janitra_private.owner_erasure_running() returns boolean
language sql volatile security definer set search_path='' as $$
 select exists(select 1 from janitra_private.account_deletions
  where running_xid=pg_current_xact_id()::text);
$$;
revoke all on function janitra_private.owner_erasure_running() from public,anon,authenticated,service_role;
create or replace function janitra_private.immutable_account_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' and janitra_private.owner_erasure_running() then return old; end if;
 raise exception 'Account security history is immutable' using errcode='42501';
end $$;

create function janitra_private.erase_deleted_auth_account() returns trigger
language plpgsql security definer set search_path='' as $$
declare approval janitra_private.account_deletions%rowtype;
 tasks uuid[]; rules uuid[]; shifts uuid[]; transfers uuid[];
begin
 if not exists(select 1 from public.profiles where id=old.id) then return old; end if;
 perform pg_advisory_xact_lock(hashtextextended('erase/'||old.id::text,0));
 select * into approval from janitra_private.account_deletions where target_id=old.id for update;
 if not found or approval.expires_at<=clock_timestamp() then raise exception 'Owner deletion confirmation required' using errcode='42501'; end if;
 perform 1 from auth.sessions where id=approval.session_id and user_id=approval.owner_id for share;
 perform 1 from public.profiles where id=approval.owner_id for share;
 perform 1 from janitra_private.account_owners where user_id=approval.owner_id for share;
 if not public.owner_account_access(approval.owner_id,approval.session_id)
  or exists(select 1 from janitra_private.account_owners where user_id=old.id) then
  raise exception 'Owner authorization changed' using errcode='42501';
 end if;
 perform 1 from public.profiles where id=old.id for update;
 update janitra_private.account_deletions set running_xid=pg_current_xact_id()::text where target_id=old.id;
 select coalesce(array_agg(id),'{}') into shifts from public.shift_templates where user_id=old.id;
 select coalesce(array_agg(id),'{}') into rules from public.task_schedule_rules where user_id=old.id or shift_id=any(shifts);
 select coalesce(array_agg(id),'{}') into transfers from public.agency_transfers where user_id=old.id or actor_id=old.id;
 select coalesce(array_agg(t.id),'{}') into tasks from public.task_instances t where t.user_id=old.id
  or t.rule_id=any(rules) or t.verified_by=old.id or t.decided_by=old.id
  or exists(select 1 from public.supervisor_confirmations x where x.task_id=t.id and x.actor_id=old.id)
  or exists(select 1 from public.approval_events x where x.task_id=t.id and x.actor_id=old.id)
  or exists(select 1 from public.lock_overrides x where x.task_id=t.id and x.actor_id=old.id)
  or exists(select 1 from public.task_events x where x.task_id=t.id and x.actor_id=old.id);
 delete from public.task_notifications where task_id=any(tasks) or recipient_id=old.id;
 delete from public.employee_pin_confirmation_events where task_id=any(tasks) or actor_id=old.id;
 delete from public.supervisor_confirmations where task_id=any(tasks) or actor_id=old.id;
 delete from public.approval_events where task_id=any(tasks) or actor_id=old.id;
 delete from public.lock_overrides where task_id=any(tasks) or actor_id=old.id;
 delete from public.task_events where task_id=any(tasks) or actor_id=old.id;
 delete from public.task_submissions where task_id=any(tasks) or user_id=old.id;
 delete from public.task_instances where id=any(tasks);
 delete from public.schedule_exceptions where rule_id=any(rules) or substitute_id=old.id;
 delete from public.task_schedule_rules where id=any(rules);
 delete from public.shift_segments where template_id=any(shifts);
 delete from public.shift_templates where id=any(shifts);
 delete from public.activity_checklist_versions where actor_id=old.id;
 delete from public.report_exports where actor_id=old.id or strpos(filters::text,old.id::text)>0;
 delete from janitra_private.workflow_requests r where actor_id=old.id or strpos(result::text,old.id::text)>0
  or exists(select 1 from unnest(tasks) t(id) where strpos(r.result::text,t.id::text)>0);
 delete from public.account_security_events where user_id=old.id or actor_id=old.id;
 delete from public.audit_events where actor_id=old.id or entity_id=old.id
  or strpos(coalesce(before_data::text,''),old.id::text)>0 or strpos(coalesce(after_data::text,''),old.id::text)>0;
 delete from janitra_private.account_setup_grants where user_id=old.id or issued_by=old.id;
 delete from janitra_private.identity_revoked_sessions where user_id=old.id;
 delete from janitra_private.personnel_identities where user_id=old.id;
 -- Retain other people's accounts and usable credentials after their creator is erased.
 update janitra_private.personnel_identities set created_by=approval.owner_id where created_by=old.id;
 delete from janitra_private.employee_pin_credentials where user_id=old.id;
 delete from janitra_private.supervisor_pin_credentials where user_id=old.id;
 update janitra_private.employee_pin_credentials set changed_by=approval.owner_id where changed_by=old.id;
 update janitra_private.supervisor_pin_credentials set changed_by=approval.owner_id where changed_by=old.id;
 delete from public.role_assignments where user_id=old.id or ended_by_transfer=any(transfers);
 delete from public.personnel_assignments where user_id=old.id;
 delete from public.agency_transfers where id=any(transfers);
 delete from janitra_private.supervisor_bootstrap_grants where user_id=old.id;
 delete from janitra_private.account_deletions where owner_id=old.id;
 delete from public.profiles where id=old.id;
 delete from janitra_private.account_deletions where target_id=old.id;
 return old;
end $$;
revoke all on function janitra_private.erase_deleted_auth_account() from public,anon,authenticated,service_role;
create trigger janitra_erase_account before delete on auth.users
 for each row execute function janitra_private.erase_deleted_auth_account();
commit;
