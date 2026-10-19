\set ON_ERROR_STOP on
begin;
create function public.company_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at)
 select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'company-'||n||'@test.invalid',now() from generate_series(991,998) n;
insert into public.profiles(id,full_name) select id,email from auth.users where email like 'company-%';
insert into public.agencies(id,name) values
 ('10000000-0000-0000-0000-000000000991','Company A'),('10000000-0000-0000-0000-000000000992','Company B');
insert into public.client_companies(id,agency_id,name) values
 ('20000000-0000-0000-0000-000000000991','10000000-0000-0000-0000-000000000991','Client A'),
 ('20000000-0000-0000-0000-000000000992','10000000-0000-0000-0000-000000000992','Client B');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000991','10000000-0000-0000-0000-000000000991','20000000-0000-0000-0000-000000000991','Site A'),
 ('30000000-0000-0000-0000-000000000992','10000000-0000-0000-0000-000000000992','20000000-0000-0000-0000-000000000992','Site B'),
 ('30000000-0000-0000-0000-000000000993','10000000-0000-0000-0000-000000000991','20000000-0000-0000-0000-000000000991','Site A2');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000991',null,null,'admin'),
 ('00000000-0000-0000-0000-000000000992','10000000-0000-0000-0000-000000000991',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000993','10000000-0000-0000-0000-000000000991','30000000-0000-0000-0000-000000000991','supervisor'),
 ('00000000-0000-0000-0000-000000000994','10000000-0000-0000-0000-000000000992','30000000-0000-0000-0000-000000000992','personnel'),
 ('00000000-0000-0000-0000-000000000995','10000000-0000-0000-0000-000000000992','30000000-0000-0000-0000-000000000992','supervisor'),
 ('00000000-0000-0000-0000-000000000996','10000000-0000-0000-0000-000000000991','30000000-0000-0000-0000-000000000991','personnel'),
 ('00000000-0000-0000-0000-000000000997','10000000-0000-0000-0000-000000000991','30000000-0000-0000-0000-000000000993','personnel');
create function public.company_work(actor uuid,action text,data jsonb) returns jsonb language sql as $$
 select public.workflow_command(actor,actor,action,jsonb_build_object('request_id',gen_random_uuid(),
 'agency_id','10000000-0000-0000-0000-000000000992','site_id','30000000-0000-0000-0000-000000000992')||data);
$$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000992","role":"authenticated"}',true);
select public.company_assert((select count(*)=2 from public.agencies where name like 'Company %'),'Company-Wide reads both manpower companies');
select public.company_assert((select count(*)=3 from public.sites where id in('30000000-0000-0000-0000-000000000991','30000000-0000-0000-0000-000000000992','30000000-0000-0000-0000-000000000993')),'Company-Wide reads sites across companies');
update public.client_companies set name='Edited Client B' where id='20000000-0000-0000-0000-000000000992';
select public.company_assert(exists(select 1 from public.client_companies where name='Edited Client B'),'Company-Wide can manage another company workplace records');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000993","role":"authenticated"}',true);
select public.company_assert(not exists(select 1 from public.agencies where id='10000000-0000-0000-0000-000000000992'),'site-specific company list remains scoped');
select public.company_assert(not exists(select 1 from public.sites where id in('30000000-0000-0000-0000-000000000992','30000000-0000-0000-0000-000000000993')),'site-specific site list remains scoped');
select public.company_assert(not has_function_privilege('authenticated','public.owner_list_accounts(uuid,uuid)','execute'),'directory actor cannot be forged by client');
select public.company_assert(not has_table_privilege('authenticated','public.role_assignments','insert,update,delete'),'client cannot grant Company-Wide or Admin roles');
select public.company_assert(not has_function_privilege('authenticated','janitra_private.is_company_wide_supervisor(uuid)','execute'),'Company-Wide authority helper stays private');
select public.company_assert(not exists(select 1 from public.role_assignments where user_id='00000000-0000-0000-0000-000000000991'),'Company-Wide scope does not expose global Admin assignment');
reset role;
do $$
declare a uuid:='00000000-0000-0000-0000-000000000991'; wide uuid:='00000000-0000-0000-0000-000000000992';
 scoped uuid:='00000000-0000-0000-0000-000000000993'; employee uuid:='00000000-0000-0000-0000-000000000994';
 supervisor uuid:='00000000-0000-0000-0000-000000000995'; spare uuid:='00000000-0000-0000-0000-000000000998';
 home uuid:='10000000-0000-0000-0000-000000000991'; agency uuid:='10000000-0000-0000-0000-000000000992';
 site uuid:='30000000-0000-0000-0000-000000000992'; home_site uuid:='30000000-0000-0000-0000-000000000991';
 activity uuid:=gen_random_uuid(); shift uuid:=gen_random_uuid(); rule uuid:=gen_random_uuid(); task uuid; late_task uuid;
 result jsonb; users jsonb; before_roles integer; before_history integer;
begin
 perform public.company_assert(janitra_private.manager_has_scope(wide,agency,site),'Company-Wide manages a foreign site');
 perform public.company_assert(not janitra_private.manager_has_scope(scoped,agency,site),'site-specific cannot manage foreign site');
 perform public.company_assert(not janitra_private.manager_has_scope(employee,agency,site),'Personnel never obtains Supervisor rights');
 perform public.company_assert(public.can_invite_user(wide,agency,site,'personnel'),'Company-Wide may invite foreign Personnel');
 perform public.company_assert(not public.can_invite_user(wide,agency,null,'supervisor') and not public.can_invite_user(wide,agency,null,'admin'),'Company-Wide cannot invite privileged roles');
 perform public.company_assert(public.finish_user_invite(wide,spare,'company-998@test.invalid',agency,site,'personnel','New Personnel')='assigned','Company-Wide assigns Personnel in another company');
 perform public.company_assert(public.edit_personnel(wide,wide,employee,'Edited foreign Personnel'),'Company-Wide edits foreign Personnel');
 perform public.set_personnel_access(wide,employee,agency,site,false);
 perform public.company_assert(not exists(select 1 from public.role_assignments where user_id=employee and is_active),'Company-Wide suspends foreign Personnel');
 perform public.set_personnel_access(wide,employee,agency,site,true);
 perform public.company_assert(exists(select 1 from public.role_assignments where user_id=employee and is_active),'Company-Wide restores foreign Personnel');
 perform public.company_assert(public.can_delete_account(wide,wide,employee),'Company-Wide may delete Personnel across companies');
 perform public.company_assert(not public.can_delete_account(wide,wide,supervisor) and not public.can_delete_account(wide,wide,a),'Company-Wide cannot delete Supervisors or Admin');
 begin perform public.manage_supervisor(wide,wide,supervisor,agency,null,true,'Forbidden'); raise exception 'FAIL: Supervisor authority escalation';
 exception when insufficient_privilege then raise notice 'PASS: Company-Wide cannot modify Supervisor permissions'; end;
 begin perform public.set_personnel_access(wide,supervisor,agency,site,false); raise exception 'FAIL: Supervisor suspension through Personnel API';
 exception when insufficient_privilege then raise notice 'PASS: Supervisor suspension remains Admin-only'; end;
 perform public.set_pin_credential(wide,employee,'employee',agency,site,repeat('a',64));
 perform public.set_pin_credential(wide,wide,'supervisor',agency,null,repeat('b',64));
 perform public.company_assert(janitra_private.verify_pin(wide,'supervisor',agency,site,repeat('b',64))='verified','Company-Wide Supervisor PIN works across companies');
 perform public.company_assert(not public.can_manage_pin(wide,supervisor,'supervisor',agency,site),'Company-Wide cannot reset another Supervisor PIN');
 perform public.company_assert(not public.can_manage_pin(scoped,employee,'employee',agency,site),'site-specific cannot reset foreign Personnel PIN');
 perform public.company_assert((public.company_work(wide,'activity_save',jsonb_build_object('id',activity,'name','Cross-company cleaning'))->>'ok')::boolean,'Company-Wide creates foreign activity');
 perform public.company_assert((public.company_work(wide,'shift_save',jsonb_build_object('id',shift,'user_id',employee,'name','Cross-company shift',
  'weekdays','[1,2,3,4,5,6,7]'::jsonb,'starts_on',current_date,'segments','[{"start":0,"end":1439,"kind":"work"}]'::jsonb))->>'ok')::boolean,'Company-Wide creates foreign work shift');
 perform public.company_assert((public.company_work(wide,'rule_save',jsonb_build_object('id',rule,'user_id',employee,'activity_id',activity,
  'weekdays','[1,2,3,4,5,6,7]'::jsonb,'starts_on',current_date,'at_minute',0,'until_minute',0))->>'ok')::boolean,'Company-Wide creates foreign cleaning schedule');
 perform janitra_private.generate_work(current_date,current_date+2,agency);
 select id into strict task from public.task_instances where rule_id=rule order by scheduled_at limit 1;
 update public.task_instances set status='SCHEDULED',scheduled_at=clock_timestamp()-interval '1 minute',original_deadline=clock_timestamp()+interval '1 hour',review_deadline=clock_timestamp()+interval '1 hour' where id=task;
 perform public.company_assert((public.company_work(employee,'submit',jsonb_build_object('task_id',task,'version',0,'digest',repeat('a',64),'remarks','Completed'))->>'ok')::boolean,'Personnel submission still needs its own PIN');
 perform public.company_assert((public.company_work(wide,'approve',jsonb_build_object('task_id',task,'version',1))->>'code')='unverified','Company-Wide cannot bypass Supervisor verification');
 perform public.company_assert((public.company_work(wide,'verify',jsonb_build_object('task_id',task,'version',1,'digest',repeat('b',64)))->>'ok')::boolean,'Company-Wide verifies foreign task using Supervisor PIN');
 perform public.company_assert((public.company_work(wide,'approve',jsonb_build_object('task_id',task,'version',2))->>'ok')::boolean,'Company-Wide separately approves foreign task');
 perform public.company_assert(exists(select 1 from public.approval_events where task_id=task and actor_id=wide and outcome='APPROVED'),'cross-company approval retains immutable history');
 perform public.company_assert(exists(select 1 from public.task_notifications where task_id=task and recipient_id=wide),'Company-Wide receives cross-company submission notifications');
 result:=public.company_work(wide,'report',jsonb_build_object('from_date',current_date-1,'to_date',current_date+3,'format','xlsx'));
 perform public.company_assert((result->>'ok')::boolean and jsonb_array_length(result->'records')>0,'Company-Wide reports foreign company work');
 begin perform public.company_work(scoped,'activity_save',jsonb_build_object('name','Forbidden')); raise exception 'FAIL: site-specific changed foreign schedules';
 exception when insufficient_privilege then raise notice 'PASS: site-specific cannot manage foreign schedules'; end;
 begin perform public.company_work(scoped,'verify',jsonb_build_object('task_id',task,'version',3,'digest',repeat('b',64))); raise exception 'FAIL: site-specific reviewed foreign work';
 exception when insufficient_privilege then raise notice 'PASS: site-specific cannot review foreign tasks'; end;
 select id into strict late_task from public.task_instances where rule_id=rule and id<>task order by scheduled_at limit 1;
 update public.task_instances set status='PENDING_APPROVAL',submitted_at=clock_timestamp(),review_deadline=clock_timestamp()-interval '1 second' where id=late_task;
 result:=public.company_work(wide,'verify',jsonb_build_object('task_id',late_task,'version',0,'digest',repeat('b',64)));
 perform public.company_assert(not (result->>'ok')::boolean and exists(select 1 from public.task_instances where id=late_task and status='LOCKED_NOT_REVIEWED'),'cross-company authority still enforces deadline locking');
 perform public.company_assert((public.company_work(wide,'override',jsonb_build_object('task_id',late_task,'version',(select version from public.task_instances where id=late_task),
  '_reauth',true,'reason','Authorized cross-company review','deadline',clock_timestamp()+interval '1 hour'))->>'ok')::boolean,'Company-Wide can perform authorized foreign deadline reopening');
 perform public.company_assert((public.company_work(wide,'activity_delete',jsonb_build_object('id',activity))->>'deleted')::boolean,'Company-Wide can retire foreign scheduling items');
 perform public.company_assert(exists(select 1 from public.task_instances where id=task and status='APPROVED'),'retiring schedules preserves approved work');
 users:=public.owner_list_accounts(wide,wide);
 perform public.company_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=employee::text and x->>'email'='company-994@test.invalid' and (x->>'can_delete')::boolean),'Company-Wide roster includes cross-company management information');
 perform public.company_assert(not exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=a::text),'Admin remains hidden from company-wide roster');
 perform public.personnel_identity_command(wide,wide,'issue_grant',jsonb_build_object('user_id',spare,'agency_id',agency,'site_id',site,'purpose','recovery','reason','Verified identity across companies','digest',repeat('d',64)));
 perform public.company_assert(exists(select 1 from janitra_private.account_setup_grants where user_id=spare and issued_by=wide),'Company-Wide issues foreign Personnel recovery code');
 perform public.owner_prepare_account_deletion(wide,wide,employee,'DELETE');
 delete from auth.users where id=employee;
 perform public.company_assert(exists(select 1 from public.task_instances where id=task) and exists(select 1 from public.approval_events where task_id=task),'cross-company deletion preserves task and approval history');
 select count(*) into before_roles from public.role_assignments where user_id=wide;
 insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000993','Future Company');
 perform public.company_assert(janitra_private.manager_has_scope(wide,'10000000-0000-0000-0000-000000000993',null)
  and (select count(*)=before_roles from public.role_assignments where user_id=wide),'Company-Wide covers future companies without role grants');
 update public.profiles set is_active=false where id=wide;
 perform public.company_assert(not janitra_private.manager_has_scope(wide,agency,site),'suspended Company-Wide account loses all-company authority');
 update public.profiles set is_active=true where id=wide;
 update public.role_assignments set is_active=false where user_id=wide;
 insert into public.role_assignments(user_id,agency_id,site_id,role) values(wide,home,home_site,'supervisor');
 perform public.company_assert(not janitra_private.manager_has_scope(wide,agency,site) and janitra_private.manager_has_scope(wide,home,home_site),'downgrade immediately restores site-specific limits');
 begin perform public.company_work(wide,'report',jsonb_build_object('from_date',current_date,'to_date',current_date,'format','pdf')); raise exception 'FAIL: downgraded account retained foreign reports';
 exception when insufficient_privilege then raise notice 'PASS: downgrade denies cross-company operations'; end;
 delete from auth.sessions where user_id=wide;
 begin perform public.owner_list_accounts(wide,wide); raise exception 'FAIL: expired account read directory';
 exception when insufficient_privilege then raise notice 'PASS: expired session denied after Company-Wide downgrade'; end;
end $$;
rollback;
