begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
do $$ begin
  if to_regprocedure('extensions.crypt(text,text)') is null then
    raise exception 'pgcrypto must be available in the extensions schema';
  end if;
end $$;

-- PIN operations go through checked RPCs; even the Edge service role has no raw table access.
revoke all on janitra_private.employee_pin_credentials, janitra_private.supervisor_pin_credentials from service_role;

create function janitra_private.pin_scope(p_actor uuid, p_target uuid,
  p_kind text, p_agency uuid, p_site uuid, p_reset boolean)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id=p_actor and p.is_active)
    and exists(select 1 from public.profiles p where p.id=p_target and p.is_active)
    and (p_site is null or exists(select 1 from public.sites s where s.id=p_site and s.agency_id=p_agency))
    and case p_kind
      when 'supervisor' then p_actor=p_target and exists (
        select 1 from public.role_assignments r where r.user_id=p_actor
          and r.agency_id=p_agency and r.role='supervisor' and r.is_active
          and (r.site_id is null or r.site_id=p_site)
      )
      when 'employee' then p_site is not null
        and janitra_private.manager_has_scope(p_actor,p_agency,p_site)
        and exists(select 1 from public.role_assignments r where r.user_id=p_target
          and r.agency_id=p_agency and r.site_id=p_site and r.role='personnel' and r.is_active)
        -- A global account PIN cannot be reset by a manager of only one of its sites.
        and (not p_reset or not exists (
          select 1 from public.role_assignments r where r.user_id=p_target
            and r.role='personnel' and r.is_active
            and not janitra_private.manager_has_scope(p_actor,r.agency_id,r.site_id)
        ))
      else false end;
$$;
revoke all on function janitra_private.pin_scope(uuid,uuid,text,uuid,uuid,boolean)
  from public, anon, authenticated, service_role;

create function public.can_manage_pin(p_actor uuid, p_target uuid,
  p_kind text, p_agency uuid, p_site uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select janitra_private.pin_scope(p_actor,p_target,p_kind,p_agency,p_site,true);
$$;
revoke all on function public.can_manage_pin(uuid,uuid,text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.can_manage_pin(uuid,uuid,text,uuid,uuid) to service_role;

create function public.pin_status(p_actor uuid, p_target uuid,
  p_kind text, p_agency uuid, p_site uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare configured_at timestamptz;
begin
  if not janitra_private.pin_scope(p_actor,p_target,p_kind,p_agency,p_site,false) then
    raise exception 'PIN status not authorized' using errcode='42501';
  end if;
  if p_kind='employee' then
    select changed_at into configured_at from janitra_private.employee_pin_credentials where user_id=p_target;
  else
    select changed_at into configured_at from janitra_private.supervisor_pin_credentials where user_id=p_target;
  end if;
  return jsonb_build_object('configured',configured_at is not null,'changed_at',configured_at,
    'can_reset',janitra_private.pin_scope(p_actor,p_target,p_kind,p_agency,p_site,true));
end;
$$;
revoke all on function public.pin_status(uuid,uuid,text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.pin_status(uuid,uuid,text,uuid,uuid) to service_role;

create function public.set_pin_credential(p_actor uuid, p_target uuid,
  p_kind text, p_agency uuid, p_site uuid, p_digest text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare credential_table text; before_time timestamptz; after_time timestamptz;
begin
  if not public.can_manage_pin(p_actor,p_target,p_kind,p_agency,p_site)
    or p_digest is null or p_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'PIN change not authorized' using errcode='42501';
  end if;
  credential_table := case p_kind when 'employee' then 'employee_pin_credentials' else 'supervisor_pin_credentials' end;
  -- Serialize initial enrollment and resets, including two callers racing to enroll.
  perform 1 from public.profiles where id=p_target for update;
  execute format('select changed_at from janitra_private.%I where user_id=$1',credential_table)
    into before_time using p_target;
  after_time := clock_timestamp();
  execute format('insert into janitra_private.%I(user_id,pin_hash,changed_by,changed_at)
    values($1,extensions.crypt($2,extensions.gen_salt(''bf'',12)),$3,$4)
    on conflict(user_id) do update set pin_hash=excluded.pin_hash, changed_by=excluded.changed_by,
      changed_at=excluded.changed_at,failed_attempts=0,locked_until=null',credential_table)
    using p_target,p_digest,p_actor,after_time;
  insert into public.audit_events(actor_id,agency_id,site_id,entity_type,entity_id,action,before_data,after_data)
    values(p_actor,p_agency,p_site,credential_table,p_target,
      case when before_time is null then 'insert' else 'update' end,
      jsonb_build_object('configured',before_time is not null,'changed_at',before_time),
      jsonb_build_object('configured',true,'changed_at',after_time));
  return jsonb_build_object('configured',true,'changed_at',after_time);
end;
$$;
revoke all on function public.set_pin_credential(uuid,uuid,text,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.set_pin_credential(uuid,uuid,text,uuid,uuid,text) to service_role;

-- Task submission/review RPCs will call this internally and commit its failed
-- attempts even when no task transition is accepted; no reusable verification API.
create function janitra_private.verify_pin(p_user uuid,p_kind text,p_agency uuid,p_site uuid,p_digest text)
returns text language plpgsql security definer set search_path = '' as $$
declare credential_table text; stored_hash text; attempts integer; locked timestamptz; now_at timestamptz;
begin
  if p_digest is null or p_digest !~ '^[0-9a-f]{64}$'
    or p_kind is null or p_kind not in ('employee','supervisor')
    or (p_site is not null and not exists(select 1 from public.sites s where s.id=p_site and s.agency_id=p_agency))
    or not exists(select 1 from public.profiles p where p.id=p_user and p.is_active)
    or not exists(select 1 from public.role_assignments r where r.user_id=p_user
      and r.agency_id=p_agency and r.is_active
      and r.role=case p_kind when 'employee' then 'personnel' else 'supervisor' end
      and (r.site_id=p_site or (p_kind='supervisor' and r.site_id is null))) then
    return 'denied';
  end if;
  credential_table := case p_kind when 'employee' then 'employee_pin_credentials' else 'supervisor_pin_credentials' end;
  execute format('select pin_hash,failed_attempts,locked_until from janitra_private.%I
    where user_id=$1 for update',credential_table) into stored_hash,attempts,locked using p_user;
  if stored_hash is null then return 'not_configured'; end if;
  now_at := clock_timestamp();
  if locked is not null and locked>now_at then return 'locked'; end if;
  if locked is not null then attempts:=0; end if;
  if extensions.crypt(p_digest,stored_hash)=stored_hash then
    execute format('update janitra_private.%I set failed_attempts=0,locked_until=null where user_id=$1',credential_table)
      using p_user;
    return 'verified';
  end if;
  attempts := attempts+1;
  execute format('update janitra_private.%I set failed_attempts=$2,locked_until=$3 where user_id=$1',credential_table)
    using p_user,attempts,case when attempts>=5 then now_at+interval '15 minutes' else null end;
  return case when attempts>=5 then 'locked' else 'incorrect' end;
end;
$$;
revoke all on function janitra_private.verify_pin(uuid,text,uuid,uuid,text)
  from public, anon, authenticated, service_role;

commit;
