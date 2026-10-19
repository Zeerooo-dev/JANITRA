\set ON_ERROR_STOP on
begin;
create function public.schedule_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at) select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'test'||n||'@example.test',now() from generate_series(21,24) n;
insert into public.profiles(id,full_name) select id,'Schedule test' from auth.users where email in ('test21@example.test','test22@example.test','test23@example.test','test24@example.test');
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000021','Schedule agency');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','Client');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021','Site A'),
 ('30000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021','Site B');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000021','30000000-0000-0000-0000-000000000021','personnel'),
 ('00000000-0000-0000-0000-000000000023','10000000-0000-0000-0000-000000000021','30000000-0000-0000-0000-000000000022','supervisor');
select public.schedule_assert(not has_function_privilege('authenticated','public.workflow_command(uuid,uuid,text,jsonb)','EXECUTE') and not has_function_privilege('service_role','public.workflow_command_before_schedule_deletion(uuid,uuid,text,jsonb)','EXECUTE'),'schedule deletion cannot bypass its service-only wrapper');
select public.schedule_assert(not has_table_privilege('authenticated','public.work_activities','DELETE,UPDATE'),'clients cannot directly delete or restore activities');
do $$
declare manager uuid:='00000000-0000-0000-0000-000000000021'; worker uuid:='00000000-0000-0000-0000-000000000022';
 partial_manager uuid:='00000000-0000-0000-0000-000000000023'; agency uuid:='10000000-0000-0000-0000-000000000021'; site uuid:='30000000-0000-0000-0000-000000000021';
 activity uuid:=gen_random_uuid(); shift uuid:=gen_random_uuid(); rule uuid:=gen_random_uuid(); second_rule uuid:=gen_random_uuid();
 future_task uuid:=gen_random_uuid(); submitted_task uuid:=gen_random_uuid(); past_task uuid:=gen_random_uuid();
 args jsonb; outcome jsonb; idempotent jsonb;
begin
 insert into public.work_activities(id,agency_id,site_id,name) values(activity,agency,site,'Delete test');
 insert into public.shift_templates(id,agency_id,site_id,user_id,name,weekdays,starts_on) values(shift,agency,site,worker,'Shift',array[1,2,3,4,5,6,7],current_date);
 insert into public.shift_segments(template_id,agency_id,site_id,start_minute,end_minute,kind) values(shift,agency,site,0,1440,'work');
 insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,shift_id,weekdays,starts_on,at_minute,until_minute)
  values(rule,agency,site,worker,activity,shift,array[1,2,3,4,5,6,7],current_date,480,480);
 insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
 select id,rule,agency,site,worker,current_date,slot,current_date,planned,now()+interval '2 days',now()+interval '2 days','Delete test','','','Agency','Client','Site','Person'
 from (values(future_task,480,now()+interval '1 hour'),(submitted_task,481,now()-interval '1 minute'),(past_task,482,now()-interval '2 minutes')) v(id,slot,planned);
 insert into public.task_submissions(task_id,agency_id,site_id,user_id,remarks) values(submitted_task,agency,site,worker,'Keep official history');
 update public.task_instances set status='PENDING_APPROVAL',submitted_at=now() where id=submitted_task;
 args:=jsonb_build_object('id',activity,'agency_id',agency,'site_id',site,'request_id',gen_random_uuid());
 begin
  perform public.workflow_command(worker,worker,'activity_delete',args);
  raise exception 'FAIL: Personnel deleted activity';
 exception when insufficient_privilege then raise notice 'PASS: Personnel scheduling deletion denied'; end;
 begin
  perform public.workflow_command(partial_manager,partial_manager,'activity_delete',args);
  raise exception 'FAIL: out-of-scope Supervisor deleted activity';
 exception when insufficient_privilege then raise notice 'PASS: out-of-scope Supervisor scheduling deletion denied'; end;
 begin
  perform public.workflow_command(manager,manager,'activity_delete',args||jsonb_build_object('site_id','30000000-0000-0000-0000-000000000022'));
  raise exception 'FAIL: spoofed site accepted';
 exception when insufficient_privilege then raise notice 'PASS: target scope is checked against stored activity'; end;
 update auth.sessions set not_after=now()-interval '1 second' where id=manager;
 begin
  perform public.workflow_command(manager,manager,'activity_delete',args);
  raise exception 'FAIL: expired session deleted activity';
 exception when insufficient_privilege then raise notice 'PASS: expired session cannot delete scheduling items'; end;
 update auth.sessions set not_after=null where id=manager;
 outcome:=public.workflow_command(manager,manager,'activity_delete',args);
 perform public.schedule_assert(outcome->>'deleted'='true' and outcome->>'cancelled_future_tasks'='1','deleting an activity removes linked schedules and only future unsubmitted tasks');
 perform public.schedule_assert((select deleted_at is not null and not is_active from public.work_activities where id=activity) and (select deleted_at is not null and not is_active from public.task_schedule_rules where id=rule),'activity and linked schedule cannot generate work');
 perform public.schedule_assert((select status='CANCELLED' and version=1 from public.task_instances where id=future_task),'future draft task is cancelled and version invalidated');
 perform public.schedule_assert((select status='SCHEDULED' from public.task_instances where id=past_task),'already-due work remains available');
 perform public.schedule_assert((select status='PENDING_APPROVAL' from public.task_instances where id=submitted_task) and (select remarks='Keep official history' from public.task_submissions where task_id=submitted_task),'submitted work and its snapshot are preserved');
 idempotent:=public.workflow_command(manager,manager,'activity_delete',args);
 perform public.schedule_assert(outcome=idempotent and (select count(*)=1 from public.audit_events where entity_id=activity and action='delete'),'lost deletion response retries without duplicate audit');
 begin
  perform public.workflow_command(manager,manager,'rule_delete',args||jsonb_build_object('id',rule));
  raise exception 'FAIL: request identifier reused for another target';
 exception when unique_violation then raise notice 'PASS: deletion retry bound to action and target'; end;
 perform janitra_private.generate_work(current_date,current_date+1,agency);
 perform public.schedule_assert((select status='CANCELLED' from public.task_instances where id=future_task),'work generation cannot revive deleted schedules');
 begin
  perform public.workflow_command(manager,manager,'activity_save',args||jsonb_build_object('request_id',gen_random_uuid(),'name','Restore','is_active',true));
  raise exception 'FAIL: deleted activity edited';
 exception when raise_exception then if sqlerrm not like 'This schedule item was deleted%' then raise; end if; raise notice 'PASS: stale edit cannot restore a deleted activity'; end;
 begin
  update public.work_activities set deleted_at=null,is_active=true where id=activity;
  raise exception 'FAIL: direct restore accepted';
 exception when raise_exception then if sqlerrm not like 'This schedule item was deleted%' then raise; end if; raise notice 'PASS: deleted activity remains a tombstone'; end;
 begin
  perform public.workflow_command(manager,manager,'rule_save',jsonb_build_object('request_id',gen_random_uuid(),'activity_id',activity,'agency_id',agency,'site_id',site));
  raise exception 'FAIL: deleted activity reused for a new schedule';
 exception when raise_exception then if sqlerrm not like 'This schedule item was deleted%' then raise; end if; raise notice 'PASS: new schedules cannot reference deleted activities'; end;
 perform public.set_pin_credential(manager,manager,'supervisor',agency,null,repeat('e',64));
 outcome:=public.workflow_command(manager,manager,'verify',jsonb_build_object('request_id',gen_random_uuid(),'task_id',submitted_task,'version',0,'digest',repeat('e',64)));
 outcome:=public.workflow_command(manager,manager,'approve',jsonb_build_object('request_id',gen_random_uuid(),'task_id',submitted_task,'version',(outcome->'task'->>'version')::integer));
 perform public.schedule_assert(outcome->'task'->>'status'='APPROVED','submitted work can still be reviewed after its activity is deleted');
 insert into public.work_activities(agency_id,site_id,name) values(agency,site,'Remaining activity') returning id into activity;
 insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,shift_id,weekdays,starts_on,at_minute,until_minute)
  values(second_rule,agency,site,worker,activity,shift,array[1,2,3,4,5,6,7],current_date,500,500);
 outcome:=public.workflow_command(manager,manager,'shift_delete',jsonb_build_object('id',shift,'agency_id',agency,'site_id',site,'request_id',gen_random_uuid()));
 perform public.schedule_assert(outcome->>'deleted'='true' and (select deleted_at is not null from public.task_schedule_rules where id=second_rule),'shift deletion removes dependent cleaning schedules');
 insert into public.task_schedule_rules(agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute)
  values(agency,site,worker,activity,array[1,2,3,4,5,6,7],current_date,510,510) returning id into second_rule;
 outcome:=public.workflow_command(manager,manager,'rule_delete',jsonb_build_object('id',second_rule,'agency_id',agency,'site_id',site,'request_id',gen_random_uuid()));
 perform public.schedule_assert(outcome->>'deleted'='true' and (select deleted_at is null from public.work_activities where id=activity),'cleaning schedule deletion keeps its reusable activity');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'session_id',worker,'role','authenticated')::text,true);
 set local role authenticated;
 perform public.schedule_assert(not exists(select 1 from public.shift_templates where id=shift) and not exists(select 1 from public.shift_segments where template_id=shift),'Personnel schedules and segments hide deleted work shifts');
 perform public.schedule_assert(not exists(select 1 from public.task_schedule_rules where id=rule) and exists(select 1 from public.task_submissions where task_id=submitted_task),'Personnel cannot see deleted schedules but retain official history');
 reset role;
end $$;
rollback;
