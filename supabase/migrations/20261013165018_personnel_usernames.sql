begin;

create table janitra_private.personnel_identities (
 id uuid primary key, user_id uuid unique references auth.users(id) on delete restrict,
 username text unique check(username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
 login_email text not null unique, contact_email text, full_name text not null check(length(btrim(full_name)) between 1 and 200),
 agency_id uuid not null references public.agencies(id), site_id uuid not null,
 created_by uuid not null references public.profiles(id),
 state text not null default 'setup_pending' check(state in ('setup_pending','active','recovery_pending','suspended')),
 created_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table janitra_private.account_setup_grants (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 digest text not null unique check(digest ~ '^[0-9a-f]{64}$'), purpose text not null check(purpose in ('setup','recovery')),
 issued_by uuid not null references public.profiles(id), issuer_session uuid not null,
 agency_id uuid not null references public.agencies(id), site_id uuid not null,
 expires_at timestamptz not null default clock_timestamp()+interval '30 minutes',
 state text not null default 'issued' check(state in ('issued','claimed','consumed','revoked','failed')),
 claim_id uuid unique, claimed_at timestamptz, consumed_at timestamptz,
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create index account_grants_owner_idx on janitra_private.account_setup_grants(user_id,state);
create index account_grants_expiry_idx on janitra_private.account_setup_grants(expires_at);
create table janitra_private.identity_attempt_windows (
 kind text not null check(kind in ('identifier','grant','global')), digest text not null check(digest ~ '^[0-9a-f]{64}$'),
 window_start timestamptz not null, attempts integer not null check(attempts>0), primary key(kind,digest,window_start)
);
create index identity_attempt_expiry_idx on janitra_private.identity_attempt_windows(window_start);
create table janitra_private.identity_revoked_sessions (
 session_id uuid primary key, user_id uuid not null references auth.users(id),
 revoked_at timestamptz not null default clock_timestamp()
);
alter table janitra_private.personnel_identities enable row level security;
alter table janitra_private.account_setup_grants enable row level security;
alter table janitra_private.identity_attempt_windows enable row level security;
alter table janitra_private.identity_revoked_sessions enable row level security;
revoke all on janitra_private.identity_revoked_sessions from public,anon,authenticated,service_role;
create or replace function janitra_private.live_auth_session() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s where s.user_id=auth.uid() and s.id=
  case when (auth.jwt()->>'session_id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   then (auth.jwt()->>'session_id')::uuid else null end and (s.not_after is null or s.not_after>clock_timestamp())
  and not exists(select 1 from janitra_private.identity_revoked_sessions r where r.session_id=s.id));
$$;
create or replace function public.actor_session_valid(p_actor uuid,p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s join public.profiles p on p.id=s.user_id where s.id=p_session and s.user_id=p_actor and p.is_active and (s.not_after is null or s.not_after>clock_timestamp())
  and not exists(select 1 from janitra_private.identity_revoked_sessions r where r.session_id=s.id)
  and exists(select 1 from public.role_assignments r where r.user_id=p_actor and r.is_active));
$$;
create or replace function public.actor_session_state(p_actor uuid,p_session uuid) returns text language sql stable security definer set search_path='' as $$
 select case when not exists(select 1 from public.profiles where id=p_actor and is_active) then 'suspended'
  when not exists(select 1 from public.role_assignments where user_id=p_actor and is_active) then 'revoked'
  when not exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()))
   or exists(select 1 from janitra_private.identity_revoked_sessions where session_id=p_session) then 'expired' else 'active' end;
$$;
create table public.account_security_events (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 actor_id uuid not null references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 action text not null check(action in ('setup_issued','recovery_issued','password_setup_completed','password_recovery_completed','password_setup_rejected','password_recovery_rejected','suspended','reactivated')),
 reason text not null default '' check(length(reason)<=1000), occurred_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create index account_security_scope_idx on public.account_security_events(agency_id,site_id,occurred_at);
alter table public.account_security_events enable row level security;
revoke all on public.account_security_events from public,anon,authenticated,service_role;
grant select on public.account_security_events to authenticated;
create policy account_security_read on public.account_security_events for select to authenticated
 using(janitra_private.can_read_work(user_id,agency_id,site_id));
create function janitra_private.immutable_account_event() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Account security history is immutable' using errcode='42501'; end;
$$;
create trigger immutable_account_security before update or delete on public.account_security_events
 for each row execute function janitra_private.immutable_account_event();
revoke all on function janitra_private.immutable_account_event() from public,anon,authenticated,service_role;
revoke all on janitra_private.personnel_identities,janitra_private.account_setup_grants,janitra_private.identity_attempt_windows from public,anon,authenticated,service_role;

create function public.personnel_identity_command(p_actor uuid,p_session uuid,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i janitra_private.personnel_identities%rowtype; g janitra_private.account_setup_grants%rowtype;
 username_value text; agency uuid; site uuid; target uuid; operation uuid; authority uuid; authority_session uuid;
 kind_value text; digest_value text; window_value timestamptz; attempt_count integer; maximum integer;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 then
  raise exception 'Invalid identity request' using errcode='22023';
 end if;
 if p_action='claim_grant' then
  select user_id,issued_by,issuer_session into target,authority,authority_session from janitra_private.account_setup_grants where digest=p_data->>'digest';
 elsif p_action in ('finish_grant','reject_grant') then
  select user_id,issued_by,issuer_session into target,authority,authority_session from janitra_private.account_setup_grants where claim_id=(p_data->>'claim_id')::uuid;
 elsif p_action in ('issue_grant','finish_provision') then
  target:=(p_data->>'user_id')::uuid;
 end if;
 if target is not null then perform pg_advisory_xact_lock(hashtextextended('identity/'||target::text,0)); end if;
 if p_action in ('reserve','issue_grant','finish_provision') then authority:=p_actor; authority_session:=p_session; end if;
 if authority is not null then
  perform 1 from auth.sessions where id=authority_session and user_id=authority for share;
  perform 1 from public.profiles where id=authority for share;
  perform 1 from public.role_assignments where user_id=authority and role='supervisor' and is_active for share;
 end if;
 if p_action='rate' then
  kind_value:=p_data->>'kind'; digest_value:=p_data->>'digest';
  if kind_value not in ('identifier','grant','global') or digest_value !~ '^[0-9a-f]{64}$' then raise exception 'Invalid rate request'; end if;
  window_value:=to_timestamp(floor(extract(epoch from clock_timestamp())/case when kind_value='global' then 60 else 900 end)*case when kind_value='global' then 60 else 900 end);
  maximum:=case when kind_value='global' then 60 else 5 end;
  delete from janitra_private.identity_attempt_windows where window_start<clock_timestamp()-interval '1 day';
  insert into janitra_private.identity_attempt_windows values(kind_value,digest_value,window_value,1)
   on conflict(kind,digest,window_start) do update set attempts=least(janitra_private.identity_attempt_windows.attempts+1,61) returning attempts into attempt_count;
  return jsonb_build_object('allowed',attempt_count<=maximum);
 end if;
 if p_action='login_lookup' then
  select * into i from janitra_private.personnel_identities where username=lower(btrim(p_data->>'identifier')) and state='active';
  if not found or i.user_id is null or not exists(select 1 from public.profiles p where p.id=i.user_id and p.is_active)
   or not exists(select 1 from public.role_assignments r where r.user_id=i.user_id and r.is_active and r.role='personnel') then return '{}'::jsonb; end if;
  return jsonb_build_object('login_email',i.login_email,'user_id',i.user_id);
 end if;
 if p_action='claim_grant' then
  select * into g from janitra_private.account_setup_grants where digest=p_data->>'digest' for update;
  if not found or g.state<>'issued' or g.expires_at<=clock_timestamp() then return '{}'::jsonb; end if;
  select * into i from janitra_private.personnel_identities where user_id=g.user_id for update;
  if not found or p_data->>'identifier' is null or i.state not in ('setup_pending','recovery_pending') or lower(btrim(p_data->>'identifier')) not in (coalesce(i.username,''),lower(i.login_email))
   or not public.actor_session_valid(g.issued_by,g.issuer_session)
   or not janitra_private.manager_has_scope(g.issued_by,g.agency_id,g.site_id)
   or exists(select 1 from public.role_assignments r where r.user_id=i.user_id and r.is_active and not janitra_private.manager_has_scope(g.issued_by,r.agency_id,r.site_id)) then return '{}'::jsonb; end if;
  update janitra_private.account_setup_grants set state='claimed',claim_id=gen_random_uuid(),claimed_at=clock_timestamp() where id=g.id returning * into g;
  return jsonb_build_object('claim_id',g.claim_id,'user_id',i.user_id,'login_email',i.login_email);
 end if;
 if p_action='reject_grant' then
  select * into g from janitra_private.account_setup_grants where claim_id=(p_data->>'claim_id')::uuid for update;
  if not found or g.state<>'claimed' then return '{}'::jsonb; end if;
  update janitra_private.account_setup_grants set state='failed' where id=g.id;
  insert into public.account_security_events(user_id,actor_id,agency_id,site_id,action)
   values(g.user_id,g.user_id,g.agency_id,g.site_id,case when g.purpose='setup' then 'password_setup_rejected' else 'password_recovery_rejected' end);
  return jsonb_build_object('rejected',true);
 end if;
 if p_action='finish_grant' then
  select * into g from janitra_private.account_setup_grants where claim_id=(p_data->>'claim_id')::uuid for update;
  if not found or g.state<>'claimed' or g.expires_at<=clock_timestamp() or not public.actor_session_valid(g.issued_by,g.issuer_session)
   or not janitra_private.manager_has_scope(g.issued_by,g.agency_id,g.site_id) then raise exception 'Setup cannot be completed safely' using errcode='42501'; end if;
  select * into i from janitra_private.personnel_identities where user_id=g.user_id for update;
  if i.state not in ('setup_pending','recovery_pending') or exists(select 1 from public.role_assignments r where r.user_id=i.user_id and r.is_active and not janitra_private.manager_has_scope(g.issued_by,r.agency_id,r.site_id)) then raise exception 'Setup authority changed' using errcode='42501'; end if;
  if not exists(select 1 from auth.users u where u.id=i.user_id and u.email_confirmed_at is not null and coalesce(u.encrypted_password,'')<>'') then raise exception 'Auth password setup incomplete'; end if;
  insert into janitra_private.identity_revoked_sessions(session_id,user_id)
   select s.id,s.user_id from auth.sessions s where s.user_id=i.user_id on conflict do nothing;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g.issued_by,'role','authenticated')::text,true);
  update public.profiles set is_active=true where id=i.user_id;
  if g.purpose='setup' then
   update public.role_assignments set is_active=true where user_id=i.user_id and agency_id=g.agency_id and site_id=g.site_id and role='personnel';
   update public.personnel_assignments set is_active=true where user_id=i.user_id and agency_id=g.agency_id and site_id=g.site_id and ends_on is null;
  end if;
  update janitra_private.personnel_identities set state='active' where id=i.id;
  update janitra_private.account_setup_grants set state='consumed',consumed_at=clock_timestamp() where id=g.id;
  insert into public.account_security_events(user_id,actor_id,agency_id,site_id,action) values(i.user_id,i.user_id,g.agency_id,g.site_id,case when g.purpose='setup' then 'password_setup_completed' else 'password_recovery_completed' end);
  return jsonb_build_object('completed',true);
 end if;
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Current Supervisor session required' using errcode='42501'; end if;
 agency:=(p_data->>'agency_id')::uuid; site:=(p_data->>'site_id')::uuid;
 if not janitra_private.manager_has_scope(p_actor,agency,site) then raise exception 'Supervisor scope required' using errcode='42501'; end if;
 if p_action='reserve' then
  operation:=(p_data->>'request_id')::uuid; username_value:=lower(btrim(p_data->>'username'));
  if username_value is null or username_value !~ '^[a-z0-9][a-z0-9._-]{2,31}$' or length(btrim(p_data->>'full_name')) not between 1 and 200
   or not exists(select 1 from public.sites where id=site and agency_id=agency) then raise exception 'Check username, name and workplace' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(operation::text,0));
  select * into i from janitra_private.personnel_identities where id=operation;
  if found then
   if i.created_by<>p_actor or i.username<>username_value or i.agency_id<>agency or i.site_id<>site or i.full_name<>btrim(p_data->>'full_name') or i.contact_email is distinct from nullif(btrim(p_data->>'email'),'') then raise exception 'Provisioning request changed' using errcode='22023'; end if;
  else
   insert into janitra_private.personnel_identities(id,username,login_email,contact_email,full_name,agency_id,site_id,created_by)
    values(operation,username_value,encode(extensions.gen_random_bytes(24),'hex')||'@personnel.janitra.invalid',nullif(btrim(p_data->>'email'),''),btrim(p_data->>'full_name'),agency,site,p_actor) returning * into i;
  end if;
  select u.id into target from auth.users u where lower(u.email)=i.login_email and u.raw_app_meta_data->>'janitra_provisioning_id'=operation::text;
  return jsonb_build_object('operation_id',i.id,'login_email',i.login_email,'existing_user_id',coalesce(i.user_id,target));
 end if;
 if p_action='finish_provision' then
  select * into i from janitra_private.personnel_identities where id=(p_data->>'request_id')::uuid for update;
  target:=(p_data->>'user_id')::uuid;
  if not found or i.created_by<>p_actor or i.agency_id<>agency or i.site_id<>site or i.state<>'setup_pending'
   or (i.user_id is not null and i.user_id<>target)
   or not exists(select 1 from auth.users u where u.id=target and u.email=i.login_email and u.raw_app_meta_data->>'janitra_provisioning_id'=i.id::text) then raise exception 'Invalid provisioning result' using errcode='42501'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated')::text,true);
  insert into public.profiles(id,full_name,is_active) values(target,i.full_name,false) on conflict(id) do nothing;
  insert into public.role_assignments(user_id,agency_id,site_id,role,is_active) values(target,agency,site,'personnel',false) on conflict(user_id,agency_id,site_id) do nothing;
  insert into public.personnel_assignments(user_id,agency_id,site_id,starts_on,is_active) values(target,agency,site,(clock_timestamp() at time zone 'Asia/Manila')::date,false) on conflict(user_id,site_id,starts_on) do nothing;
  update janitra_private.personnel_identities set user_id=target where id=i.id;
  return jsonb_build_object('user_id',target);
 end if;
 if p_action='issue_grant' then
  target:=(p_data->>'user_id')::uuid;
  perform 1 from public.profiles where id=target for update;
  if target=p_actor or not exists(select 1 from public.role_assignments r where r.user_id=target and r.role='personnel' and r.agency_id=agency and r.site_id=site)
   or exists(select 1 from public.role_assignments r where r.user_id=target and r.role='supervisor')
   or exists(select 1 from public.role_assignments r where r.user_id=target and r.is_active and not janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id)) then raise exception 'Account recovery not authorized' using errcode='42501'; end if;
  select * into i from janitra_private.personnel_identities where user_id=target for update;
  if not found then
   insert into janitra_private.personnel_identities(id,user_id,login_email,full_name,agency_id,site_id,created_by,state)
    select gen_random_uuid(),u.id,u.email,p.full_name,agency,site,p_actor,'active' from auth.users u join public.profiles p on p.id=u.id where u.id=target returning * into i;
  end if;
  if p_data->>'purpose' not in ('setup','recovery') or (p_data->>'purpose'='setup' and i.state<>'setup_pending')
   or (p_data->>'purpose'='recovery' and i.state not in ('active','recovery_pending')) or i.state='suspended'
   or (p_data->>'digest') !~ '^[0-9a-f]{64}$'
   or (p_data->>'purpose'='recovery' and length(btrim(p_data->>'reason')) not between 10 and 1000) then raise exception 'Invalid setup or recovery request' using errcode='22023'; end if;
  if exists(select 1 from janitra_private.account_setup_grants where user_id=target and claimed_at is not null and consumed_at is null and state<>'failed') then
   raise exception 'Password change is in progress. Reconciliation is required before issuing another code.' using errcode='55000';
  end if;
  update janitra_private.account_setup_grants set state='revoked' where user_id=target and state in ('issued','claimed');
  insert into janitra_private.account_setup_grants(user_id,digest,purpose,issued_by,issuer_session,agency_id,site_id)
   values(target,p_data->>'digest',p_data->>'purpose',p_actor,p_session,agency,site) returning * into g;
  if g.purpose='recovery' then
   insert into janitra_private.identity_revoked_sessions(session_id,user_id)
    select s.id,s.user_id from auth.sessions s where s.user_id=target on conflict do nothing;
   update janitra_private.personnel_identities set state='recovery_pending' where user_id=target;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated')::text,true);
   update public.profiles set is_active=false where id=target;
  end if;
  insert into public.account_security_events(user_id,actor_id,agency_id,site_id,action,reason) values(target,p_actor,agency,site,case when g.purpose='setup' then 'setup_issued' else 'recovery_issued' end,coalesce(p_data->>'reason',''));
  return jsonb_build_object('expires_at',g.expires_at,'identifier',coalesce(i.username,i.login_email));
 end if;
 raise exception 'Unknown identity action' using errcode='22023';
end;
$$;
revoke all on function public.personnel_identity_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.personnel_identity_command(uuid,uuid,text,jsonb) to service_role;

alter function public.list_managed_users(uuid,uuid) rename to list_managed_users_without_identity;
revoke all on function public.list_managed_users_without_identity(uuid,uuid) from public,anon,authenticated,service_role;
create function public.list_managed_users(p_actor uuid,p_agency uuid)
returns table(user_id uuid,email text,full_name text,role text,site_id uuid,is_active boolean,is_transferred boolean,username text,account_status text)
language sql stable security definer set search_path='' as $$
 select x.user_id,case when i.username is not null then coalesce(i.contact_email,'') else x.email end,x.full_name,x.role,x.site_id,x.is_active,x.is_transferred,i.username,
  coalesce(i.state,case when x.is_active then 'active' else 'suspended' end)
 from public.list_managed_users_without_identity(p_actor,p_agency) x
 left join janitra_private.personnel_identities i on i.user_id=x.user_id;
$$;
revoke all on function public.list_managed_users(uuid,uuid) from public,anon,authenticated;
grant execute on function public.list_managed_users(uuid,uuid) to service_role;

alter function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) rename to set_personnel_access_without_identity;
revoke all on function public.set_personnel_access_without_identity(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
create function public.set_personnel_access(p_actor uuid,p_target uuid,p_agency uuid,p_site uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('identity/'||p_target::text,0));
 perform 1 from janitra_private.personnel_identities where user_id=p_target for update;
 if p_active and exists(select 1 from janitra_private.personnel_identities where user_id=p_target and state in ('setup_pending','recovery_pending')) then raise exception 'Password setup must finish before activation' using errcode='42501'; end if;
 perform public.set_personnel_access_without_identity(p_actor,p_target,p_agency,p_site,p_active);
 update janitra_private.personnel_identities set state=case when exists(select 1 from public.role_assignments where user_id=p_target and is_active) then 'active' else 'suspended' end where user_id=p_target and state not in ('setup_pending','recovery_pending');
 if not p_active then update janitra_private.account_setup_grants set state='revoked' where user_id=p_target and state in ('issued','claimed'); end if;
 if exists(select 1 from janitra_private.personnel_identities where user_id=p_target) then insert into public.account_security_events(user_id,actor_id,agency_id,site_id,action) values(p_target,p_actor,p_agency,p_site,case when p_active then 'reactivated' else 'suspended' end); end if;
end;
$$;
revoke all on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_personnel_access(uuid,uuid,uuid,uuid,boolean) to service_role;
commit;
