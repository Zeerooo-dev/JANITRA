begin;
alter table public.work_activities add column deleted_at timestamptz,
 add constraint deleted_activity_inactive check(deleted_at is null or not is_active);
alter table public.shift_templates add column deleted_at timestamptz,
 add constraint deleted_shift_inactive check(deleted_at is null or not is_active);
alter table public.task_schedule_rules add column deleted_at timestamptz,
 add constraint deleted_rule_inactive check(deleted_at is null or not is_active);

alter policy work_read on public.work_activities using(deleted_at is null and janitra_private.has_site_role(agency_id,site_id,array['supervisor','personnel']));
alter policy work_read on public.shift_templates using(deleted_at is null and janitra_private.can_read_work(user_id,agency_id,site_id));
alter policy work_read on public.task_schedule_rules using(deleted_at is null and janitra_private.can_read_work(user_id,agency_id,site_id));

create function janitra_private.prevent_schedule_restore() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.deleted_at is not null and (new.deleted_at is distinct from old.deleted_at or new.is_active) then
  raise exception 'This schedule item was deleted. Refresh schedules before continuing.';
 end if;
 return new;
end $$;
revoke all on function janitra_private.prevent_schedule_restore() from public,anon,authenticated,service_role;
create trigger activity_stays_deleted before update on public.work_activities for each row execute function janitra_private.prevent_schedule_restore();
create trigger shift_stays_deleted before update on public.shift_templates for each row execute function janitra_private.prevent_schedule_restore();
create trigger rule_stays_deleted before update on public.task_schedule_rules for each row execute function janitra_private.prevent_schedule_restore();

do $$ declare definition text; begin
 definition:=pg_get_functiondef('janitra_private.generate_work(date,date,uuid)'::regprocedure);
 if strpos(definition,E'begin\n if p_until')=0 then raise exception 'Unexpected work generator definition'; end if;
 -- Generation and scheduling mutations share one transaction lock, so deleted work cannot reappear.
 definition:=replace(definition,E'begin\n if p_until',E'begin\n perform pg_advisory_xact_lock(hashtextextended(''janitra.schedule-generation'',0));\n if p_until');
 execute definition;
end $$;

alter function public.workflow_command(uuid,uuid,text,jsonb) rename to workflow_command_before_schedule_deletion;
revoke all on function public.workflow_command_before_schedule_deletion(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function public.workflow_command(p_actor uuid,p_session uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare agency uuid:=(p_data->>'agency_id')::uuid; site uuid:=(p_data->>'site_id')::uuid;
 item uuid:=(p_data->>'id')::uuid; req uuid:=(p_data->>'request_id')::uuid;
 before_row jsonb; result jsonb; receipt janitra_private.workflow_requests%rowtype;
 binding text; rule_ids uuid[]; cancelled integer:=0; retired integer:=0; now_at timestamptz;
begin
 if p_action not in ('activity_save','shift_save','rule_save','exception_save','policy_save','activity_delete','shift_delete','rule_delete') then
  return public.workflow_command_before_schedule_deletion(p_actor,p_session,p_action,p_data);
 end if;
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor for share;
 perform 1 from public.profiles where id=p_actor and is_active for share;
 perform 1 from public.role_assignments where user_id=p_actor and is_active and role='supervisor'
  and agency_id=agency and (site_id is null or site_id=site) for share;
 if not janitra_private.manager_has_scope(p_actor,agency,site) then raise exception 'Scheduling not authorized' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('janitra.schedule-generation',0));
 if not public.actor_session_valid(p_actor,p_session) then raise exception 'Session expired' using errcode='42501'; end if;
 if p_action in ('activity_save','shift_save','rule_save','exception_save','policy_save') then
  if (p_action='activity_save' and exists(select 1 from public.work_activities where id=item and deleted_at is not null))
   or (p_action='shift_save' and exists(select 1 from public.shift_templates where id=item and deleted_at is not null))
   or (p_action='rule_save' and (exists(select 1 from public.task_schedule_rules where id=item and deleted_at is not null)
    or exists(select 1 from public.work_activities where id=(p_data->>'activity_id')::uuid and deleted_at is not null)
    or exists(select 1 from public.shift_templates where id=(p_data->>'shift_id')::uuid and deleted_at is not null)))
   or (p_action='exception_save' and exists(select 1 from public.task_schedule_rules where id=(p_data->>'rule_id')::uuid and deleted_at is not null)) then
   raise exception 'This schedule item was deleted. Refresh schedules before continuing.';
  end if;
  return public.workflow_command_before_schedule_deletion(p_actor,p_session,p_action,p_data);
 end if;
 if item is null or req is null then raise exception 'Choose a scheduling item and request identifier'; end if;
 binding:=encode(extensions.digest((p_data-'digest'-'password'-'pin')::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||req::text,0));
 select * into receipt from janitra_private.workflow_requests where actor_id=p_actor and request_id=req;
 if found then
  if receipt.action<>p_action or receipt.binding<>binding then raise exception 'Request conflict' using errcode='23505'; end if;
  return receipt.result;
 end if;
 now_at:=clock_timestamp();
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','session_id',p_session)::text,true);
 if p_action='activity_delete' then
  select to_jsonb(a) into before_row from public.work_activities a where id=item and agency_id=agency and site_id=site for update;
 elsif p_action='shift_delete' then
  select to_jsonb(s) into before_row from public.shift_templates s where id=item and agency_id=agency and site_id=site for update;
 else
  select to_jsonb(r) into before_row from public.task_schedule_rules r where id=item and agency_id=agency and site_id=site for update;
 end if;
 if before_row is null then raise exception 'Scheduling item not authorized' using errcode='42501'; end if;
 if before_row->>'deleted_at' is null then
  if p_action='activity_delete' then
   update public.work_activities set is_active=false,deleted_at=now_at where id=item;
   select coalesce(array_agg(id),'{}') into rule_ids from public.task_schedule_rules where activity_id=item;
  elsif p_action='shift_delete' then
   update public.shift_templates set is_active=false,deleted_at=now_at where id=item;
   select coalesce(array_agg(id),'{}') into rule_ids from public.task_schedule_rules where shift_id=item;
  else rule_ids:=array[item];
  end if;
  update public.task_schedule_rules set is_active=false,deleted_at=now_at where id=any(rule_ids) and deleted_at is null;
  get diagnostics retired=row_count;
  update public.task_instances set status='CANCELLED',version=version+1
   where rule_id=any(rule_ids) and status='SCHEDULED' and submitted_at is null and scheduled_at>now_at;
  get diagnostics cancelled=row_count;
  insert into public.audit_events(actor_id,agency_id,site_id,entity_type,entity_id,action,before_data,after_data)
   values(p_actor,agency,site,p_action,item,'delete',before_row,jsonb_build_object('deleted_at',now_at,'removed_schedules',retired,'cancelled_future_tasks',cancelled));
 end if;
 result:=jsonb_build_object('ok',true,'id',item,'deleted',true,'removed_schedules',retired,'cancelled_future_tasks',cancelled);
 insert into janitra_private.workflow_requests(actor_id,request_id,action,binding,result) values(p_actor,req,p_action,binding,result);
 return result;
end $$;
revoke all on function public.workflow_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.workflow_command(uuid,uuid,text,jsonb) to service_role;
commit;
