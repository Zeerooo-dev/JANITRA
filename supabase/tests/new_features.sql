\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end; $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000001','manager@example.test',now());
insert into public.profiles(id,full_name) values('00000000-0000-0000-0000-000000000001','Manager');
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000001','Agency');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Client');
insert into public.sites(id,agency_id,client_company_id,name) values('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Site');
insert into public.role_assignments(user_id,agency_id,role) values('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','supervisor');
select public.test_assert(not has_function_privilege('authenticated','public.personnel_identity_command(uuid,uuid,text,jsonb)','EXECUTE'),'identity operations are service-only');
select public.test_assert(not has_table_privilege('service_role','janitra_private.personnel_identities','SELECT'),'identity mapping has no direct service table grant');
select public.test_assert(not has_table_privilege('authenticated','public.account_security_events','UPDATE,DELETE,TRUNCATE'),'account security history cannot be changed by clients');

do $$
declare
 manager uuid:='00000000-0000-0000-0000-000000000001';
 worker uuid:='00000000-0000-0000-0000-000000000002';
 agency uuid:='10000000-0000-0000-0000-000000000001';
 site uuid:='30000000-0000-0000-0000-000000000001';
 operation uuid:=gen_random_uuid();
 args jsonb; identity jsonb; grant_result jsonb; claim jsonb; outcome jsonb;
 fresh_session uuid:=gen_random_uuid(); n integer;
begin
 args:=jsonb_build_object('agency_id',agency,'site_id',site,'request_id',operation,'username','person.one','full_name','Personnel','email','');
 identity:=public.personnel_identity_command(manager,manager,'reserve',args);
 perform public.test_assert(identity=public.personnel_identity_command(manager,manager,'reserve',args),'provisioning retries reuse the identity reservation');
 begin
  perform public.personnel_identity_command(manager,manager,'reserve',args||jsonb_build_object('request_id',gen_random_uuid(),'username','PERSON.ONE'));
  raise exception 'FAIL: duplicate username accepted';
 exception when unique_violation then raise notice 'PASS: case-insensitive username uniqueness'; end;
 begin
  perform public.personnel_identity_command(manager,manager,'reserve',args||'{"full_name":"Changed"}'::jsonb);
  raise exception 'FAIL: request mutation accepted';
 exception when invalid_parameter_value then raise notice 'PASS: provisioning request is bound to its inputs'; end;
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
  values(worker,identity->>'login_email',now(),jsonb_build_object('janitra_provisioning_id',operation));
 perform public.personnel_identity_command(manager,manager,'finish_provision',args||jsonb_build_object('user_id',worker));
 perform public.test_assert(not public.actor_session_valid(worker,worker),'unfinished account has no workplace access');
 args:=jsonb_build_object('agency_id',agency,'site_id',site,'user_id',worker,'purpose','setup','digest',repeat('a',64));
 perform public.personnel_identity_command(manager,manager,'issue_grant',args);
 perform public.test_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','wrong','digest',repeat('a',64)))='{}'::jsonb,'code cannot be redeemed for a different identifier');
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','PERSON.ONE','digest',repeat('a',64)));
 perform public.test_assert(claim ? 'claim_id','valid setup code can be claimed');
 perform public.test_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','person.one','digest',repeat('a',64)))='{}'::jsonb,'a concurrent second redemption is denied');
 begin
  perform public.personnel_identity_command(manager,manager,'issue_grant',args||jsonb_build_object('digest',repeat('b',64)));
  raise exception 'FAIL: overlapping credential changes accepted';
 exception when object_not_in_prerequisite_state then raise notice 'PASS: in-flight password changes cannot overlap a replacement'; end;
 outcome:=public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 perform public.test_assert(outcome->>'completed'='true','setup completes and activates scoped Personnel');
 perform public.test_assert(not public.actor_session_valid(worker,worker),'pre-setup sessions remain revoked after activation');
 insert into auth.sessions(id,user_id) values(fresh_session,worker);
 perform public.test_assert(public.actor_session_valid(worker,fresh_session),'fresh session can use the completed Personnel account');
 perform public.test_assert((select username='person.one' and email='' from public.list_managed_users(manager,agency) where user_id=worker),'team list hides internal login aliases');
 perform public.personnel_identity_command(manager,manager,'issue_grant',args||jsonb_build_object('purpose','recovery','digest',repeat('c',64),'reason','Identity verified in person'));
 perform public.test_assert(not public.actor_session_valid(worker,fresh_session),'recovery immediately blocks existing access');
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','person.one','digest',repeat('c',64)));
 perform public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 perform public.test_assert(public.actor_session_state(worker,fresh_session)='expired','old sessions cannot regain access after password recovery');
 args:=args||jsonb_build_object('purpose','recovery','reason','Verified replacement after rejected password','digest',repeat('b',64));
 perform public.personnel_identity_command(manager,manager,'issue_grant',args);
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','person.one','digest',repeat('b',64)));
 perform public.personnel_identity_command(null,null,'reject_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 perform public.personnel_identity_command(manager,manager,'issue_grant',args||jsonb_build_object('digest',repeat('e',64)));
 perform public.test_assert(exists(select 1 from janitra_private.account_setup_grants where user_id=worker and state='issued' and digest=repeat('e',64)),'definitively rejected password changes can receive a replacement code');
 -- The following checklist tests need an active, completed account.
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','person.one','digest',repeat('e',64)));
 perform public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 for n in 1..6 loop
  outcome:=public.personnel_identity_command(null,null,'rate',jsonb_build_object('kind','identifier','digest',repeat('d',64)));
 end loop;
 perform public.test_assert(outcome->>'allowed'='false','identifier attempts are bounded');
end $$;

do $$
declare
 manager uuid:='00000000-0000-0000-0000-000000000001'; worker uuid:='00000000-0000-0000-0000-000000000002';
 agency uuid:='10000000-0000-0000-0000-000000000001'; site uuid:='30000000-0000-0000-0000-000000000001';
 activity uuid:=gen_random_uuid(); rule uuid:=gen_random_uuid(); task uuid:=gen_random_uuid(); session uuid:=gen_random_uuid();
 item uuid:=gen_random_uuid(); args jsonb; outcome jsonb; receipt jsonb; checks jsonb;
begin
 insert into auth.sessions(id,user_id) values(session,worker);
 args:=jsonb_build_object('request_id',gen_random_uuid(),'id',activity,'agency_id',agency,'site_id',site,'name','Cleaning','checklist_items',jsonb_build_array(jsonb_build_object('id',item,'label','Wipe counters')));
 perform public.workflow_command(manager,manager,'activity_save',args);
 perform public.test_assert((select checklist_version=1 from public.work_activities where id=activity),'activity checklist has a version');
 insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute)
  values(rule,agency,site,worker,activity,array[1,2,3,4,5,6,7],current_date,480,480);
 insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
  values(task,rule,agency,site,worker,current_date,480,current_date,clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 hour',clock_timestamp()+interval '1 hour','Cleaning','','','Agency','Client','Site','Personnel');
 perform public.test_assert((select checklist_version=1 and jsonb_array_length(checklist_items)=1 from public.task_instances where id=task),'task receives a checklist snapshot');
 args:=jsonb_build_object('request_id',gen_random_uuid(),'task_id',task,'version',0,'checklist_version',1,'digest',repeat('e',64),'claimed_at',clock_timestamp());
 outcome:=public.workflow_command(worker,session,'submit',args);
 perform public.test_assert(outcome->>'code'='checklist_incomplete','incomplete checklists do not reach official submission');
 outcome:=public.workflow_command(worker,session,'submit',args||jsonb_build_object('checklist_version',0));
 perform public.test_assert(outcome->>'code'='checklist_conflict','stale checklist versions are rejected');
 perform public.set_pin_credential(manager,worker,'employee',agency,site,repeat('e',64));
 checks:=jsonb_build_object(item::text,true);
 args:=args||jsonb_build_object('checklist_results',checks);
 outcome:=public.workflow_command(worker,session,'submit',args);
 perform public.test_assert(outcome->>'ok'='true' and outcome->'task'->>'status'='PENDING_APPROVAL','complete checklist plus Personnel PIN submits to pending approval');
 receipt:=public.workflow_command(worker,session,'submit',args);
 perform public.test_assert(receipt=outcome,'lost checklist submission response can be retried idempotently');
 perform public.test_assert((select checklist_results=checks and checklist_version=1 from public.task_submissions where task_id=task),'official submission preserves immutable checklist results');
 perform public.workflow_command(manager,manager,'activity_save',jsonb_build_object('request_id',gen_random_uuid(),'id',activity,'agency_id',agency,'site_id',site,'name','Cleaning','checklist_items','[]'::jsonb));
 perform public.test_assert((select checklist_version=1 and checklist_results=checks from public.task_instances where id=task),'activity edits cannot rewrite submitted checklist history');
 begin
  perform public.workflow_command(worker,session,'activity_save',jsonb_build_object('request_id',gen_random_uuid(),'agency_id',agency,'site_id',site,'name','Unauthorized','checklist_items','[]'::jsonb));
  raise exception 'FAIL: Personnel edited an activity';
 exception when insufficient_privilege then raise notice 'PASS: Personnel cannot edit activity checklists'; end;
end $$;
rollback;
