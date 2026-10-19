\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000001','manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000002','worker@example.test',now()),
 ('00000000-0000-0000-0000-000000000003','outsider@example.test',now());
insert into public.profiles(id,full_name) select id,email from auth.users;
insert into auth.sessions(id,user_id) select id,id from auth.users on conflict do nothing;
insert into public.agencies(id,name) values ('10000000-0000-0000-0000-000000000001','Test A'),('10000000-0000-0000-0000-000000000002','Test B');
insert into public.client_companies(id,agency_id,name) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Test Client'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Other Client');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Test Site'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Other Site');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','personnel'),
 ('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002',null,'supervisor');
create function public.test_work(actor integer,action text,data jsonb) returns jsonb language sql as $$
 select public.workflow_command(('00000000-0000-0000-0000-'||lpad(actor::text,12,'0'))::uuid,
  ('00000000-0000-0000-0000-'||lpad(actor::text,12,'0'))::uuid,action,
  jsonb_build_object('request_id',gen_random_uuid(),'agency_id','10000000-0000-0000-0000-000000000001','site_id','30000000-0000-0000-0000-000000000001')||data);
$$;
select public.test_assert(not has_function_privilege('authenticated','public.workflow_command(uuid,uuid,text,jsonb)','execute'),'client cannot forge workflow actor/session/digest');
select public.test_assert(not has_table_privilege('service_role','public.task_instances','update'),'service cannot bypass workflow transitions');
select public.test_assert(not has_table_privilege('authenticated','public.approval_events','delete'),'approval history cannot be deleted by clients');
select public.test_assert(janitra_private.work_deadline('2026-10-10 08:00+08','30000000-0000-0000-0000-000000000001')='2026-10-12 12:00+08','Saturday deadline is following Monday noon Manila');
select public.test_work(1,'activity_save','{"id":"40000000-0000-0000-0000-000000000001","name":"Clean tables","location":"Pantry","instructions":"Wipe surfaces"}');
select public.test_work(1,'shift_save',jsonb_build_object('id','50000000-0000-0000-0000-000000000001','user_id','00000000-0000-0000-0000-000000000002',
 'name','Split shift','weekdays','[1,2,3,4,5,6,7]'::jsonb,'starts_on',current_date,'segments','[{"start":420,"end":720,"kind":"work"},{"start":960,"end":1200,"kind":"work"},{"start":600,"end":630,"kind":"break"}]'::jsonb));
select public.test_work(1,'rule_save',jsonb_build_object('id','60000000-0000-0000-0000-000000000001','user_id','00000000-0000-0000-0000-000000000002',
 'activity_id','40000000-0000-0000-0000-000000000001','shift_id','50000000-0000-0000-0000-000000000001',
 'weekdays','[1,2,3,4,5,6,7]'::jsonb,'starts_on',current_date,'at_minute',420,'until_minute',1200,'interval_minutes',30));
select public.test_assert(exists(select 1 from public.task_instances),'real recurring occurrences generated');
select public.test_assert(not exists(select 1 from public.task_instances where slot_minute=600),'break excludes cleaning occurrences');
select public.test_assert(not exists(select 1 from public.task_instances where slot_minute between 720 and 959),'split-shift gap excludes work');
select public.test_assert(not exists(select 1 from public.task_instances where slot_minute=1200),'shift end is exclusive');
create temporary table counts as select count(*) n from public.task_instances;
select janitra_private.generate_work(current_date,current_date+14);
select public.test_assert((select n from counts)=(select count(*) from public.task_instances),'generation retries do not duplicate instances');
do $$ begin
 begin perform public.test_work(2,'activity_save','{"name":"Escalation"}'); raise exception 'Personnel changed schedules'; exception when insufficient_privilege then null; end;
 begin perform public.test_work(3,'activity_save','{"id":"40000000-0000-0000-0000-000000000001","name":"Foreign overwrite","agency_id":"10000000-0000-0000-0000-000000000002","site_id":"30000000-0000-0000-0000-000000000002"}'); raise exception 'Cross-scope overwrite'; exception when insufficient_privilege then null; end;
 begin perform public.workflow_command('00000000-0000-0000-0000-000000000002',gen_random_uuid(),'read_notifications',jsonb_build_object('request_id',gen_random_uuid())); raise exception 'Missing session accepted'; exception when insufficient_privilege then null; end;
end $$;
select public.test_assert((select name='Clean tables' from public.work_activities where id='40000000-0000-0000-0000-000000000001'),'unauthorized activity edits leave data intact');
select public.set_pin_credential('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','employee','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',repeat('a',64));
select public.set_pin_credential('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','supervisor','10000000-0000-0000-0000-000000000001',null,repeat('b',64));
create temporary table chosen as select id from public.task_instances order by scheduled_at limit 1;
update public.task_instances set scheduled_at=clock_timestamp()-interval '5 minutes',review_deadline=clock_timestamp()+interval '1 hour',original_deadline=clock_timestamp()+interval '1 hour' where id=(select id from chosen);
select public.test_assert((public.test_work(2,'submit',jsonb_build_object('task_id',(select id from chosen),'version',0,'digest',repeat('c',64)))->>'ok')::boolean=false,'wrong PIN does not accept submission');
select public.test_assert((select failed_attempts=1 from janitra_private.employee_pin_credentials where user_id='00000000-0000-0000-0000-000000000002'),'failed counter committed by rejected task operation');
select public.test_assert(not exists(select 1 from public.task_submissions),'wrong PIN creates no submission/event');
create temporary table request as select gen_random_uuid() id;
create temporary table submission_payload as select jsonb_build_object('request_id',(select id from request),'task_id',(select id from chosen),'version',0,'digest',repeat('a',64),'remarks','Test completion','claimed_at',clock_timestamp()) data;
create temporary table response as select public.workflow_command('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','submit',
 (select data from submission_payload)) result;
select public.test_assert(public.workflow_command('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','submit',(select data from submission_payload))=(select result from response),'lost response retries return same submission receipt');
select public.test_assert((select result->'task'->>'status'='PENDING_APPROVAL' from response),'Employee PIN atomically creates Pending Approval');
select public.test_assert((select count(*)=1 from public.task_submissions) and (select count(*)=1 from public.employee_pin_confirmation_events),'one submission and one separate Employee event');
select public.test_assert((select count(*)>0 from public.task_notifications where recipient_id='00000000-0000-0000-0000-000000000001'),'Supervisor receives submission notification');
select public.test_assert((public.test_work(1,'approve',jsonb_build_object('task_id',(select id from chosen),'version',1))->>'ok')::boolean=false,'approval requires prior Supervisor PIN');
select public.test_work(1,'verify',jsonb_build_object('task_id',(select id from chosen),'version',1,'digest',repeat('b',64)));
select public.test_assert((select status='PENDING_APPROVAL' and verified_at is not null from public.task_instances where id=(select id from chosen)),'Supervisor verification does not approve work');
select public.test_work(1,'approve',jsonb_build_object('task_id',(select id from chosen),'version',2));
select public.test_assert((select status='APPROVED' and decided_at is not null from public.task_instances where id=(select id from chosen)),'separate final decision recorded');
select public.test_assert((public.test_work(1,'reject',jsonb_build_object('task_id',(select id from chosen),'version',3,'reason','Conflicting choice'))->>'ok')::boolean=false,'conflicting final decision denied');
select public.test_work(1,'rule_save',jsonb_build_object('id','60000000-0000-0000-0000-000000000001','user_id','00000000-0000-0000-0000-000000000002',
 'activity_id','40000000-0000-0000-0000-000000000001','shift_id','50000000-0000-0000-0000-000000000001',
 'weekdays','[1,2,3,4,5,6,7]'::jsonb,'starts_on',current_date,'at_minute',480,'until_minute',1200,'interval_minutes',60));
select public.test_assert((select status='APPROVED' and activity_name='Clean tables' from public.task_instances where id=(select id from chosen)),'editing future rules preserves completed history');
create temporary table late as select id,version from public.task_instances where status='SCHEDULED' order by scheduled_at limit 1;
update public.task_instances set status='PENDING_APPROVAL',submitted_at=now(),review_deadline=clock_timestamp()-interval '1 second' where id=(select id from late);
select public.test_assert((public.test_work(1,'verify',jsonb_build_object('task_id',(select id from late),'version',(select version from late),'digest',repeat('b',64)))->>'ok')::boolean=false,'deadline enforced even before job runs');
select public.test_assert((select status='LOCKED_NOT_REVIEWED' from public.task_instances where id=(select id from late)),'expired pending record locked in transaction');
select public.test_work(1,'override',jsonb_build_object('task_id',(select id from late),'version',(select version from public.task_instances where id=(select id from late)),
 '_reauth',true,'reason','Authorized test reopening','deadline',clock_timestamp()+interval '1 hour'));
select public.test_assert((select status='REOPENED_FOR_REVIEW' and review_cycle=1 and verified_at is null from public.task_instances where id=(select id from late)),'override needs new verification and preserves cycle');
select public.test_assert((select count(*)=1 from public.lock_overrides) and exists(select 1 from public.task_events where task_id=(select id from late) and event='locked'),'original lock and override history preserved');
select public.test_work(1,'report',jsonb_build_object('from_date',current_date-1,'to_date',current_date+15,'format','xlsx'));
select public.test_assert((select count(*)=1 from public.report_exports),'authorized report export recorded');
select public.test_assert(not exists(select 1 from public.task_events where details::text ~ 'digest|pin_hash|password') and not exists(select 1 from public.audit_events where coalesce(after_data,'{}')::text ~ 'pin_hash|password|digest'),'work history and audit contain no PIN credential');
do $$ begin
 begin perform public.test_work(1,'shift_save',jsonb_build_object('user_id','00000000-0000-0000-0000-000000000002','name','Invalid overlap','weekdays','[1]'::jsonb,'starts_on',current_date,'segments','[{"start":420,"end":720,"kind":"work"},{"start":600,"end":800,"kind":"work"}]'::jsonb));raise exception 'Overlap accepted';exception when raise_exception then if sqlerrm='Overlap accepted' then raise;end if;end;
end $$;
select public.test_assert((select count(*)=1 from public.shift_templates),'overlapping schedules rejected without partial writes');
select public.set_personnel_access('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',false);
select public.test_assert(not exists(select 1 from public.task_instances where user_id='00000000-0000-0000-0000-000000000002' and status='SCHEDULED' and scheduled_at>clock_timestamp()),'suspension cancels future unsubmitted work');
do $$ begin
 begin perform public.workflow_command('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','submit',(select data from submission_payload));raise exception 'Revoked replay allowed';exception when insufficient_privilege then null;end;
end $$;
select public.set_personnel_access('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',true);
select public.test_assert(exists(select 1 from public.task_instances where status='SCHEDULED' and scheduled_at>clock_timestamp()),'reactivation restores future active schedules');
do $$ begin
 begin perform public.transfer_personnel_agency('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','Agency changed','00000000-0000-0000-0000-000000000001'); raise exception 'Transfer crossed authority'; exception when insufficient_privilege then null; end;
end $$;
insert into public.role_assignments(user_id,agency_id,role) values('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','supervisor');
select public.transfer_personnel_agency('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','Agency changed','00000000-0000-0000-0000-000000000001');
select public.test_assert(not exists(select 1 from public.role_assignments where user_id='00000000-0000-0000-0000-000000000002' and agency_id='10000000-0000-0000-0000-000000000001' and is_active),'transfer revokes old agency roles');
select public.test_assert(exists(select 1 from public.role_assignments where user_id='00000000-0000-0000-0000-000000000002' and agency_id='10000000-0000-0000-0000-000000000002' and is_active),'transfer grants only authorized destination Personnel');
select public.test_assert((select status='APPROVED' from public.task_instances where id=(select id from chosen)),'agency transfer preserves old approved work');
select public.test_assert(not exists(select 1 from public.task_schedule_rules where user_id='00000000-0000-0000-0000-000000000002' and is_active),'transfer stops future old-agency scheduling');
do $$ begin
 begin perform public.set_personnel_access('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',true);raise exception 'Retired role restored';exception when insufficient_privilege then null;end;
 begin perform public.workflow_command('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','submit',(select data from submission_payload));raise exception 'Old receipt exposed';exception when insufficient_privilege then null;end;
end $$;
select public.test_assert((select source_name='Test A' and destination_name='Test B' from public.agency_transfers),'transfer history keeps agency names');
grant select on chosen to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select public.test_assert(exists(select 1 from public.task_instances where id=(select id from chosen)),'transferred Personnel retains own history');
select public.test_assert((select count(*)=1 from public.agency_transfers),'Personnel can read their transfer history');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated","session_id":"ffffffff-ffff-ffff-ffff-ffffffffffff"}',true);
select public.test_assert(not exists(select 1 from public.task_work_view) and not exists(select 1 from public.agencies),'revoked session has no protected RLS data');
reset role;
rollback;
