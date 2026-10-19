\set ON_ERROR_STOP on
begin;
create function public.admin_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at)
 select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'admin-role-'||n||'@test.invalid',now() from generate_series(951,956) n;
insert into public.profiles(id,full_name) select id,email from auth.users where email like 'admin-role-%';
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000951','Agency A'),('10000000-0000-0000-0000-000000000952','Agency B');
insert into public.client_companies(id,agency_id,name) values
 ('20000000-0000-0000-0000-000000000951','10000000-0000-0000-0000-000000000951','Client A'),
 ('20000000-0000-0000-0000-000000000952','10000000-0000-0000-0000-000000000952','Client B');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000951','10000000-0000-0000-0000-000000000951','20000000-0000-0000-0000-000000000951','Site A'),
 ('30000000-0000-0000-0000-000000000952','10000000-0000-0000-0000-000000000951','20000000-0000-0000-0000-000000000951','Site A2'),
 ('30000000-0000-0000-0000-000000000953','10000000-0000-0000-0000-000000000952','20000000-0000-0000-0000-000000000952','Site B');
select public.admin_assert(not exists(select 1 from public.role_assignments where role='admin'),'migration promotes nobody');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000951',null,null,'admin'),
 ('00000000-0000-0000-0000-000000000952','10000000-0000-0000-0000-000000000951',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000953','10000000-0000-0000-0000-000000000951','30000000-0000-0000-0000-000000000951','personnel'),
 ('00000000-0000-0000-0000-000000000954','10000000-0000-0000-0000-000000000952',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000955','10000000-0000-0000-0000-000000000952','30000000-0000-0000-0000-000000000953','personnel');
do $$
declare a uuid:='00000000-0000-0000-0000-000000000951'; s uuid:='00000000-0000-0000-0000-000000000952';
 p uuid:='00000000-0000-0000-0000-000000000953'; other_s uuid:='00000000-0000-0000-0000-000000000954';
 other_p uuid:='00000000-0000-0000-0000-000000000955';
 agency uuid:='10000000-0000-0000-0000-000000000951'; other_agency uuid:='10000000-0000-0000-0000-000000000952';
 site uuid:='30000000-0000-0000-0000-000000000951'; site2 uuid:='30000000-0000-0000-0000-000000000952';
 activity uuid:=gen_random_uuid(); rule uuid:=gen_random_uuid(); task uuid:=gen_random_uuid(); admin_task uuid:=gen_random_uuid();
begin
 perform public.admin_assert(public.can_invite_user(a,agency,site,'supervisor'),'Admin can invite site-specific Supervisors');
 perform public.admin_assert(not public.can_invite_user(s,agency,null,'supervisor'),'Supervisor cannot invite Supervisors');
 perform public.admin_assert(not public.can_invite_user(p,agency,site,'personnel'),'Personnel cannot invite');
 perform public.admin_assert(not public.can_invite_user(a,agency,null,'admin'),'no Admin creation through invitations');
 perform public.admin_assert(public.can_delete_account(s,s,p),'Supervisor may delete scoped Personnel');
 perform public.admin_assert(not public.can_delete_account(s,s,other_p),'cross-agency Personnel deletion denied');
 perform public.admin_assert(not public.can_delete_account(s,s,other_s),'Supervisor deletion by Supervisor denied');
 perform public.admin_assert(not public.can_delete_account(p,p,s),'Personnel deletion denied');
 perform public.admin_assert(not public.can_delete_account(a,a,a),'Admin self-deletion denied');
 perform public.admin_assert(public.can_delete_account(a,a,other_s),'Admin can delete Supervisor');
 perform public.admin_assert((public.workflow_command(a,a,'activity_save',jsonb_build_object('request_id',gen_random_uuid(),
  'agency_id',other_agency,'site_id','30000000-0000-0000-0000-000000000953','name','Admin cross-agency activity'))->>'ok')::boolean,
  'Admin can manage schedules without a scoped Supervisor row');
 perform public.admin_assert((public.workflow_command(a,a,'report',jsonb_build_object('request_id',gen_random_uuid(),
  'agency_id',other_agency,'from_date',current_date,'to_date',current_date,'format','xlsx'))->>'ok')::boolean,
  'Admin can report across agencies without a scoped Supervisor row');
 begin
  perform public.manage_supervisor(s,s,other_s,agency,null,true,'Changed');
  raise exception 'FAIL: Supervisor modified Supervisor permissions';
 exception when insufficient_privilege then raise notice 'PASS: Supervisor permission editing denied'; end;
 begin
  perform public.finish_user_invite(s,s,'admin-role-952@test.invalid',agency,site,'personnel','Escalation');
  raise exception 'FAIL: Supervisor assigned Personnel scope to Supervisor';
 exception when insufficient_privilege then raise notice 'PASS: cross-role invitation denied'; end;
 perform public.manage_supervisor(a,a,other_s,agency,array[site,site2],true,'Site Supervisor');
 perform public.admin_assert(janitra_private.manager_has_scope(other_s,agency,site) and janitra_private.manager_has_scope(other_s,agency,site2)
  and not janitra_private.manager_has_scope(other_s,agency,null) and not janitra_private.manager_has_scope(other_s,other_agency,null),'multiple-site scope replaces old agency scope');
 perform public.admin_assert(not exists(select 1 from auth.sessions where user_id=other_s),'scope edit revokes old sessions');
 perform public.manage_supervisor(a,a,other_s,agency,array[site],false,'Site Supervisor');
 perform public.admin_assert(not exists(select 1 from public.profiles where id=other_s and is_active)
  and not janitra_private.manager_has_scope(other_s,agency,site),'Admin suspension removes Supervisor access');
 perform public.manage_supervisor(a,a,other_s,agency,array[site],true,'Site Supervisor');
 perform public.admin_assert(not exists(select 1 from jsonb_array_elements(public.owner_list_accounts(a,a)) x where x->>'user_id'=a::text),'Admin hidden from Team');
 perform public.admin_assert(exists(select 1 from jsonb_array_elements(public.owner_list_accounts(s,s)) x where x->>'role'='supervisor'), 'scoped Supervisor visibility preserves report filters');
 perform public.admin_assert(not exists(select 1 from jsonb_array_elements(public.owner_list_accounts(s,s)) x where x->>'role'='supervisor' and (x->>'can_delete')::boolean), 'visible Supervisors cannot be deleted by Supervisors');
 insert into public.role_assignments(user_id,agency_id,site_id,role,is_active) values(a,agency,site,'personnel',false);
 begin
  perform public.personnel_identity_command(s,s,'issue_grant',jsonb_build_object('user_id',a,'agency_id',agency,'site_id',site,'purpose','recovery','reason','Regression test','digest',repeat('a',64)));
  raise exception 'FAIL: Supervisor recovered an Admin via historical Personnel assignment';
 exception when insufficient_privilege then raise notice 'PASS: Personnel recovery cannot take over Admin accounts'; end;
 begin
  update public.profiles set is_active=false where id=a;
  raise exception 'FAIL: last Admin suspended';
 exception when insufficient_privilege then raise notice 'PASS: last active Admin suspension denied'; end;
 begin
  update public.role_assignments set is_active=false where user_id=a;
  raise exception 'FAIL: last Admin role revoked';
 exception when insufficient_privilege then raise notice 'PASS: last active Admin role revocation denied'; end;
 begin
  delete from public.role_assignments where user_id=a;
  raise exception 'FAIL: last Admin role deleted';
 exception when insufficient_privilege then raise notice 'PASS: last active Admin role deletion denied'; end;
 perform public.set_pin_credential(a,a,'supervisor',other_agency,null,repeat('a',64));
 perform public.admin_assert(janitra_private.verify_pin(a,'supervisor',other_agency,null,repeat('a',64))='verified','global Admin uses existing Supervisor verification PIN');
 perform public.set_pin_credential(s,p,'employee',agency,site,repeat('b',64));
 perform public.admin_assert(janitra_private.verify_pin(p,'employee',agency,site,repeat('b',64))='verified','Personnel PIN verification preserved');
 insert into public.work_activities(id,agency_id,site_id,name) values(activity,agency,site,'Cleaning');
 insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,weekdays,starts_on,at_minute,until_minute)
 values(rule,agency,site,p,activity,array[1,2,3,4,5,6,7],current_date,480,480);
 insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
 values(task,rule,agency,site,p,current_date,480,current_date,now(),now()+interval '1 day',now()+interval '1 day','Cleaning','','','Agency','Client','Site','Personnel');
 insert into public.task_submissions(task_id,agency_id,site_id,user_id,remarks) values(task,agency,site,p,'Test');
 insert into public.approval_events(task_id,review_cycle,actor_id,agency_id,site_id,outcome) values(task,0,s,agency,site,'APPROVED');
 insert into public.task_instances(id,rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
 values(admin_task,rule,agency,site,p,current_date,481,current_date,now(),now()+interval '1 day',now()+interval '1 day','Cleaning','','','Agency','Client','Site','Personnel');
 perform public.admin_assert((public.workflow_command(p,p,'submit',jsonb_build_object('request_id',gen_random_uuid(),'task_id',admin_task,'version',0,'digest',repeat('b',64)))->>'ok')::boolean,
  'Personnel submission still requires online Employee PIN verification');
 perform public.admin_assert((public.workflow_command(a,a,'verify',jsonb_build_object('request_id',gen_random_uuid(),'task_id',admin_task,'version',1,'digest',repeat('a',64)))->>'ok')::boolean,
  'global Admin confirms submitted work with Supervisor PIN');
 perform public.admin_assert((public.workflow_command(a,a,'approve',jsonb_build_object('request_id',gen_random_uuid(),'task_id',admin_task,'version',2))->>'ok')::boolean,
  'global Admin performs separate final approval');
 perform public.admin_assert(exists(select 1 from public.approval_events where task_id=admin_task and actor_id=a and outcome='APPROVED'),
  'Admin approval is audited under the Admin identity');
 perform janitra_private.emit_work_event(task,p,'submitted');
 perform public.admin_assert(exists(select 1 from public.task_notifications where task_id=task and recipient_id=a),'Admin receives task notifications');
 perform public.owner_prepare_account_deletion(s,s,p,'DELETE');
 insert into public.role_assignments(user_id,agency_id,site_id,role) values(p,other_agency,'30000000-0000-0000-0000-000000000953','personnel');
 begin
  delete from auth.users where id=p;
  raise exception 'FAIL: stale deletion authority accepted after scope change';
 exception when insufficient_privilege then raise notice 'PASS: deletion revalidates authority after scope changes'; end;
 delete from public.role_assignments where user_id=p and agency_id=other_agency;
 perform public.owner_prepare_account_deletion(s,s,p,'DELETE');
 delete from auth.users where id=p;
 perform public.admin_assert(not exists(select 1 from auth.sessions where user_id=p) and not exists(select 1 from auth.users where id=p),'account and sessions removed');
 perform public.admin_assert(exists(select 1 from public.profiles where id=p and not is_active and deleted_at is not null),'inactive historical profile retained');
 perform public.admin_assert(exists(select 1 from public.task_instances where id=task) and exists(select 1 from public.task_submissions where task_id=task)
  and exists(select 1 from public.approval_events where task_id=task),'deletion preserves tasks, submissions and approvals');
 perform public.admin_assert(exists(select 1 from public.audit_events where entity_id=p),'deletion preserves audit history');
 perform public.admin_assert(not exists(select 1 from janitra_private.employee_pin_credentials where user_id=p),'deleted credentials removed');
 begin
  update public.profiles set is_active=true where id=p;
  raise exception 'FAIL: tombstone restored';
 exception when insufficient_privilege then raise notice 'PASS: deleted account cannot be reactivated'; end;
 perform public.owner_prepare_account_deletion(a,a,s,'DELETE');
 delete from auth.users where id=s;
 perform public.admin_assert(exists(select 1 from public.approval_events where task_id=task and actor_id=s),'Admin deleting a Supervisor preserves their approvals');
 perform public.admin_assert(exists(select 1 from public.task_events where task_id=task),'task events survive both account deletions');
end $$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000951","role":"authenticated"}',true);
select public.admin_assert((select count(*)=2 from public.agencies where id in('10000000-0000-0000-0000-000000000951','10000000-0000-0000-0000-000000000952')),'Admin RLS spans agencies');
select public.admin_assert(not has_function_privilege('authenticated','public.manage_supervisor(uuid,uuid,uuid,uuid,uuid[],boolean,text)','execute'),'Supervisor management RPC remains service-only');
select public.admin_assert(not has_table_privilege('authenticated','public.role_assignments','insert,update,delete'),'clients cannot assign roles');
select public.admin_assert(not has_function_privilege('authenticated','public.setup_manpower_company(text,text)','execute'),'legacy bootstrap cannot create new Supervisor permissions');
reset role;
rollback;
