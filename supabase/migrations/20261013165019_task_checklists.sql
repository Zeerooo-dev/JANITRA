begin;
create function janitra_private.valid_checklist(items jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare item jsonb; ids text[]:=array[]::text[];
begin
 if jsonb_typeof(items) is distinct from 'array' then return false; end if;
 if jsonb_array_length(items)>50 then return false; end if;
 for item in select value from jsonb_array_elements(items) loop
  if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'id') is distinct from 'string'
   or (item->>'id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(item->'label') is distinct from 'string' or length(btrim(item->>'label')) not between 1 and 200
   or (item->>'id')=any(ids) or (item-'id'-'label')<>'{}'::jsonb then return false; end if;
  ids:=array_append(ids,item->>'id');
 end loop;
 return true;
end;
$$;
revoke all on function janitra_private.valid_checklist(jsonb) from public,anon,authenticated,service_role;
alter table public.work_activities add column checklist_version integer not null default 0 check(checklist_version>=0),
 add column checklist_items jsonb not null default '[]'::jsonb check(janitra_private.valid_checklist(checklist_items));
alter table public.task_instances add column checklist_version integer not null default 0,
 add column checklist_items jsonb not null default '[]'::jsonb,
 add column checklist_results jsonb not null default '{}'::jsonb;
alter table public.task_submissions add column checklist_version integer not null default 0,
 add column checklist_items jsonb not null default '[]'::jsonb,
 add column checklist_results jsonb not null default '{}'::jsonb;
create table public.activity_checklist_versions (
 activity_id uuid not null references public.work_activities(id), version integer not null check(version>0),
 agency_id uuid not null references public.agencies(id), site_id uuid not null,
 items jsonb not null check(janitra_private.valid_checklist(items)), actor_id uuid not null references public.profiles(id),
 created_at timestamptz not null default clock_timestamp(), primary key(activity_id,version),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
alter table public.activity_checklist_versions enable row level security;
revoke all on public.activity_checklist_versions from public,anon,authenticated,service_role;
grant select on public.activity_checklist_versions to authenticated;
create policy checklist_versions_read on public.activity_checklist_versions for select to authenticated
 using(janitra_private.has_site_role(agency_id,site_id,array['supervisor','personnel']));
create trigger immutable_checklist_history before update or delete on public.activity_checklist_versions
 for each row execute function janitra_private.immutable_account_event();

create function janitra_private.snapshot_task_checklist() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or (old.status='CANCELLED' and new.status='SCHEDULED' and old.submitted_at is null) then
  select a.checklist_version,a.checklist_items into new.checklist_version,new.checklist_items
   from public.task_schedule_rules r join public.work_activities a on a.id=r.activity_id where r.id=new.rule_id;
  new.checklist_version:=coalesce(new.checklist_version,0); new.checklist_items:=coalesce(new.checklist_items,'[]'::jsonb);
  new.checklist_results:='{}'::jsonb;
 end if;
 return new;
end;
$$;
revoke all on function janitra_private.snapshot_task_checklist() from public,anon,authenticated,service_role;
create trigger task_checklist_snapshot before insert or update of status on public.task_instances for each row execute function janitra_private.snapshot_task_checklist();

create function janitra_private.snapshot_submission_checklist() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.task_instances%rowtype; checks jsonb;
begin
 select * into t from public.task_instances where id=new.task_id;
 checks:=coalesce(nullif(current_setting('janitra.checklist_results',true),''),'{}')::jsonb;
 new.checklist_version:=t.checklist_version; new.checklist_items:=t.checklist_items; new.checklist_results:=checks;
 if jsonb_typeof(checks) is distinct from 'object' or (select count(*) from jsonb_object_keys(checks))<>jsonb_array_length(t.checklist_items)
  or exists(select 1 from jsonb_array_elements(t.checklist_items) item where checks->(item->>'id') is distinct from 'true'::jsonb) then
  raise exception 'Checklist results are incomplete' using errcode='22023';
 end if;
 return new;
end;
$$;
revoke all on function janitra_private.snapshot_submission_checklist() from public,anon,authenticated,service_role;
create trigger submission_checklist_snapshot before insert on public.task_submissions for each row execute function janitra_private.snapshot_submission_checklist();

alter function public.workflow_command(uuid,uuid,text,jsonb) rename to workflow_command_without_checklists;
revoke all on function public.workflow_command_without_checklists(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.workflow_command(p_actor uuid,p_session uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.task_instances%rowtype; a public.work_activities%rowtype; outcome jsonb; checks jsonb;
 req uuid; next_version integer; now_at timestamptz:=clock_timestamp();
begin
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>now_at) for share;
 if not found then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_actor and is_active for share;
 if not found then raise exception 'Account suspended' using errcode='42501'; end if;
 req:=(p_data->>'request_id')::uuid;
 -- Use the same request lock before reading a receipt or locking its task.
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||req::text,0));
 if exists(select 1 from janitra_private.workflow_requests where actor_id=p_actor and request_id=req) then
  return public.workflow_command_without_checklists(p_actor,p_session,p_action,p_data);
 end if;
 if p_action='submit' then
  select * into t from public.task_instances where id=(p_data->>'task_id')::uuid for update;
  if not found or t.user_id<>p_actor then raise exception 'Task not authorized' using errcode='42501'; end if;
  if t.checklist_version<>coalesce((p_data->>'checklist_version')::integer,0) then return jsonb_build_object('ok',false,'code','checklist_conflict','message','The assigned checklist changed. Review your draft.'); end if;
  checks:=coalesce(p_data->'checklist_results','{}'::jsonb);
  if jsonb_typeof(checks) is distinct from 'object' then raise exception 'Invalid checklist results'; end if;
  if (select count(*) from jsonb_object_keys(checks))<>jsonb_array_length(t.checklist_items)
   or exists(select 1 from jsonb_array_elements(t.checklist_items) item where checks->(item->>'id') is distinct from 'true'::jsonb) then
   return jsonb_build_object('ok',false,'code','checklist_incomplete','message','Complete every checklist item before submitting.');
  end if;
  perform set_config('janitra.checklist_results',checks::text,true);
 end if;
 if p_action='activity_save' and p_data ? 'checklist_items' and not janitra_private.valid_checklist(p_data->'checklist_items') then raise exception 'Invalid activity checklist' using errcode='22023'; end if;
 outcome:=public.workflow_command_without_checklists(p_actor,p_session,p_action,p_data);
 if outcome->>'ok'='true' and p_action='submit' then
  update public.task_instances set checklist_results=checks where id=t.id returning * into t;
  outcome:=outcome||jsonb_build_object('task',to_jsonb(t));
  update janitra_private.workflow_requests set result=outcome where actor_id=p_actor and request_id=req;
 elsif outcome->>'ok'='true' and p_action='activity_save' and p_data ? 'checklist_items' then
  select * into a from public.work_activities where id=(outcome->>'id')::uuid for update;
  if a.checklist_items is distinct from p_data->'checklist_items' then
   next_version:=a.checklist_version+1;
   insert into public.activity_checklist_versions(activity_id,version,agency_id,site_id,items,actor_id) values(a.id,next_version,a.agency_id,a.site_id,p_data->'checklist_items',p_actor);
   update public.work_activities set checklist_version=next_version,checklist_items=p_data->'checklist_items' where id=a.id;
   update public.task_instances ti set checklist_version=next_version,checklist_items=p_data->'checklist_items',version=version+1
    where ti.rule_id in(select id from public.task_schedule_rules where activity_id=a.id) and ti.status='SCHEDULED' and ti.scheduled_at>now_at and ti.submitted_at is null;
  end if;
 end if;
 return outcome;
end;
$$;
revoke all on function public.workflow_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.workflow_command(uuid,uuid,text,jsonb) to service_role;

do $$ declare columns_sql text; begin
 select string_agg(format('ti.%I',attname),',' order by attnum) into columns_sql from pg_attribute
  where attrelid='public.task_instances'::regclass and attnum>0 and not attisdropped and attname not in ('checklist_version','checklist_items','checklist_results');
 execute 'create or replace view public.task_work_view with(security_invoker=true) as select '||columns_sql||',statement_timestamp() as checked_at,
 case when ti.status in (''PENDING_APPROVAL'',''REOPENED_FOR_REVIEW'') and ti.review_deadline<=statement_timestamp() then ''LOCKED_NOT_REVIEWED''
 when ti.status=''SCHEDULED'' and ti.review_deadline<=statement_timestamp() then ''NOT_SUBMITTED'' else ti.status end as effective_status,
 ti.checklist_version,ti.checklist_items,ti.checklist_results from public.task_instances ti';
end; $$;
commit;
