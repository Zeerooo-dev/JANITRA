\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000901','race-manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000902','race-worker@example.test',now());
insert into public.profiles(id,full_name) select id,email from auth.users where id in('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902');
insert into public.agencies(id,name) values('90000000-0000-0000-0000-000000000001','Concurrency test agency');
insert into public.client_companies(id,agency_id,name) values('92000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','Test client');
insert into public.sites(id,agency_id,client_company_id,name) values('93000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','Test workplace');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000901','90000000-0000-0000-0000-000000000001',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000902','90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','personnel');
insert into public.work_activities(id,agency_id,site_id,name) values('94000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','Concurrent review');
insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute) values
 ('96000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000902','94000000-0000-0000-0000-000000000001',array[1,2,3,4,5,6,7],current_date,0,0);
insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,status,
 activity_name,location,instructions,agency_name,client_name,site_name,personnel_name,submitted_at,verified_at,verified_by,verifier_name) values
 ('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000902',current_date,0,current_date,now()-interval '1 hour',now()+interval '1 hour',now()+interval '1 hour','PENDING_APPROVAL',
 'Concurrent review','','','Test agency','Test client','Test site','Test worker',now()-interval '30 minutes',now()-interval '10 minutes','00000000-0000-0000-0000-000000000901','Test manager'),
 ('97000000-0000-0000-0000-000000000002','96000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000902','2026-10-10',1,'2026-10-10','2026-10-10 08:00+08',
 janitra_private.work_deadline('2026-10-10 08:00+08','93000000-0000-0000-0000-000000000001'),clock_timestamp(),'PENDING_APPROVAL',
 'Saturday cutoff','','','Test agency','Test client','Test site','Test worker',now()-interval '30 minutes',now()-interval '10 minutes','00000000-0000-0000-0000-000000000901','Test manager');
select public.test_assert((public.workflow_command('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000901','approve',jsonb_build_object('request_id',gen_random_uuid(),'task_id','97000000-0000-0000-0000-000000000002','version',0))->>'ok')::boolean=false,'review at exact cutoff cannot approve');
select public.test_assert((select status='LOCKED_NOT_REVIEWED' and original_deadline='2026-10-12 12:00+08' from public.task_instances where id='97000000-0000-0000-0000-000000000002'),'Saturday original Monday noon retained after cutoff lock');
commit;
