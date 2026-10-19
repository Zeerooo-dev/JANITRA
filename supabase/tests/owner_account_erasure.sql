\set ON_ERROR_STOP on
begin;
create function public.owner_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000013','owner@test.invalid',now()),
 ('00000000-0000-0000-0000-000000000014','person@test.invalid',now()),
 ('00000000-0000-0000-0000-000000000015','supervisor@test.invalid',now()),
 ('00000000-0000-0000-0000-000000000016','retained@test.invalid',now());
insert into public.profiles(id,full_name) values
 ('00000000-0000-0000-0000-000000000013','Owner'),('00000000-0000-0000-0000-000000000014','Personnel'),
 ('00000000-0000-0000-0000-000000000015','Supervisor'),('00000000-0000-0000-0000-000000000016','Retained');
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000013','Agency');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000013','Client');
insert into public.sites(id,agency_id,client_company_id,name) values('30000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000013','20000000-0000-0000-0000-000000000013','Site');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000013',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000014','10000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000013','personnel'),
 ('00000000-0000-0000-0000-000000000015','10000000-0000-0000-0000-000000000013',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000016','10000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000013','personnel');
insert into janitra_private.account_owners(user_id) values('00000000-0000-0000-0000-000000000013');
insert into janitra_private.personnel_identities(id,user_id,login_email,full_name,agency_id,site_id,created_by,state) values
 (gen_random_uuid(),'00000000-0000-0000-0000-000000000014','person@test.invalid','Personnel','10000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000015','active'),
 (gen_random_uuid(),'00000000-0000-0000-0000-000000000016','retained@test.invalid','Retained','10000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000015','active');
insert into public.account_security_events(user_id,actor_id,agency_id,site_id,action) values('00000000-0000-0000-0000-000000000014','00000000-0000-0000-0000-000000000015','10000000-0000-0000-0000-000000000013','30000000-0000-0000-0000-000000000013','reactivated');
select public.owner_assert(not has_table_privilege('authenticated','janitra_private.account_owners','SELECT,INSERT,UPDATE'),'owner permission cannot be assigned or read by clients');
select public.owner_assert(not has_function_privilege('authenticated','public.owner_prepare_account_deletion(uuid,uuid,uuid,text)','EXECUTE'),'deletion authorization is service-only');
do $$
declare owner_id uuid:='00000000-0000-0000-0000-000000000013'; worker uuid:='00000000-0000-0000-0000-000000000014';
 manager uuid:='00000000-0000-0000-0000-000000000015'; agency uuid:='10000000-0000-0000-0000-000000000013'; site uuid:='30000000-0000-0000-0000-000000000013';
 activity uuid:=gen_random_uuid(); rule uuid:=gen_random_uuid(); task uuid:=gen_random_uuid();
begin
 perform public.owner_assert(public.owner_account_access(owner_id,owner_id),'owner capability requires the original active session');
 perform public.owner_assert(not public.owner_account_access(manager,manager),'ordinary Supervisor has no owner capability');
 begin
  perform public.owner_prepare_account_deletion(manager,manager,worker,'DELETE');
  raise exception 'FAIL: ordinary Supervisor authorized erasure';
 exception when insufficient_privilege then raise notice 'PASS: ordinary Supervisor deletion denied'; end;
 begin
  perform public.owner_prepare_account_deletion(owner_id,owner_id,owner_id,'DELETE');
  raise exception 'FAIL: owner self-deletion accepted';
 exception when insufficient_privilege then raise notice 'PASS: owner account protected'; end;
 begin
  perform set_config('janitra.account_erasure','true',true);
  delete from public.account_security_events where user_id=worker;
  raise exception 'FAIL: forged erasure flag accepted';
 exception when insufficient_privilege then raise notice 'PASS: history cannot be erased by forging a session flag'; end;
 begin
  delete from auth.users where id=worker;
  raise exception 'FAIL: direct deletion bypassed owner confirmation';
 exception when insufficient_privilege then raise notice 'PASS: Auth deletion without owner request denied'; end;
 insert into public.work_activities(id,agency_id,site_id,name) values(activity,agency,site,'Cleaning');
 insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute)
  values(rule,agency,site,worker,activity,array[1,2,3,4,5,6,7],current_date,480,480);
 insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
  values(task,rule,agency,site,worker,current_date,480,current_date,now(),now()+interval '1 day',now()+interval '1 day','Cleaning','','','Agency','Client','Site','Personnel');
 insert into public.task_submissions(task_id,agency_id,site_id,user_id,remarks) values(task,agency,site,worker,'Test');
 insert into public.approval_events(task_id,review_cycle,actor_id,agency_id,site_id,outcome) values(task,0,manager,agency,site,'APPROVED');
 perform public.owner_prepare_account_deletion(owner_id,owner_id,worker,'DELETE');
 update janitra_private.account_deletions set expires_at=now()-interval '1 second' where target_id=worker;
 begin
  delete from auth.users where id=worker;
  raise exception 'FAIL: expired deletion approval accepted';
 exception when insufficient_privilege then raise notice 'PASS: stale deletion request denied'; end;
 perform public.owner_prepare_account_deletion(owner_id,owner_id,worker,'DELETE');
 delete from janitra_private.account_owners where user_id=owner_id;
 begin
  delete from auth.users where id=worker;
  raise exception 'FAIL: revoked owner capability accepted';
 exception when insufficient_privilege then raise notice 'PASS: owner capability rechecked at deletion'; end;
 insert into janitra_private.account_owners(user_id) values(owner_id);
 create table public.test_erasure_blocker(user_id uuid references auth.users(id));
 insert into public.test_erasure_blocker values(worker);
 begin
  delete from auth.users where id=worker;
  raise exception 'FAIL: unexpected constraint ignored';
 exception when foreign_key_violation then raise notice 'PASS: unexpected dependency aborts deletion'; end;
 perform public.owner_assert(exists(select 1 from public.task_instances where id=task) and exists(select 1 from public.account_security_events where user_id=worker) and exists(select 1 from public.profiles where id=worker),'failed Auth deletion rolls back tasks, history and profile');
 perform public.owner_assert(not janitra_private.owner_erasure_running(),'failed deletion cannot leave an erasure bypass');
 delete from public.test_erasure_blocker;
 delete from auth.users where id=worker;
 perform public.owner_assert(not exists(select 1 from public.profiles where id=worker) and not exists(select 1 from auth.users where id=worker) and not exists(select 1 from auth.sessions where user_id=worker),'Personnel Auth account, profile and sessions really removed');
 perform public.owner_assert(not exists(select 1 from public.task_instances where id=task) and not exists(select 1 from public.task_submissions where task_id=task) and not exists(select 1 from public.approval_events where task_id=task),'related task and review records really removed');
 perform public.owner_assert(not exists(select 1 from public.account_security_events where user_id=worker) and not exists(select 1 from public.audit_events where strpos(coalesce(after_data::text,''),worker::text)>0),'related security and audit history really removed');
 perform public.owner_prepare_account_deletion(owner_id,owner_id,manager,'DELETE');
 delete from auth.users where id=manager;
 perform public.owner_assert(not exists(select 1 from auth.users where id=manager),'Supervisor Auth account can also be removed');
 perform public.owner_assert(exists(select 1 from janitra_private.personnel_identities where user_id='00000000-0000-0000-0000-000000000016' and created_by=owner_id),'other Personnel identity survives creator deletion');
 perform public.owner_assert(exists(select 1 from public.agencies where id=agency) and exists(select 1 from public.sites where id=site),'shared workplace remains intact');
 perform public.owner_assert(not janitra_private.owner_erasure_running(),'successful deletion leaves no erasure bypass');
end $$;
rollback;
