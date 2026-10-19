\set ON_ERROR_STOP on
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000931','schedule-race-manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000932','schedule-race-worker@example.test',now());
insert into public.profiles(id,full_name) values('00000000-0000-0000-0000-000000000931','Race manager'),('00000000-0000-0000-0000-000000000932','Race worker');
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000931','Scheduling race');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000000931','10000000-0000-0000-0000-000000000931','Client');
insert into public.sites(id,agency_id,client_company_id,name) values('30000000-0000-0000-0000-000000000931','10000000-0000-0000-0000-000000000931','20000000-0000-0000-0000-000000000931','Site');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000931','10000000-0000-0000-0000-000000000931',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000932','10000000-0000-0000-0000-000000000931','30000000-0000-0000-0000-000000000931','personnel');
insert into public.work_activities(id,agency_id,site_id,name) values('40000000-0000-0000-0000-000000000931','10000000-0000-0000-0000-000000000931','30000000-0000-0000-0000-000000000931','Race activity');
insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute)
 values('60000000-0000-0000-0000-000000000931','10000000-0000-0000-0000-000000000931','30000000-0000-0000-0000-000000000931','00000000-0000-0000-0000-000000000932','40000000-0000-0000-0000-000000000931',array[1,2,3,4,5,6,7],current_date+1,480,480);
