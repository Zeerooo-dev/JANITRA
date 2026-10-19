\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %',label; end if;
  raise notice 'PASS: %',label;
end;
$$;
insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001','manager@example.test',now()),
  ('00000000-0000-0000-0000-000000000002','site-manager@example.test',now()),
  ('00000000-0000-0000-0000-000000000003','worker@example.test',now()),
  ('00000000-0000-0000-0000-000000000004','other-manager@example.test',now()),
  ('00000000-0000-0000-0000-000000000005','invited@example.test',now());
update auth.users set encrypted_password='' where id='00000000-0000-0000-0000-000000000005';
insert into public.profiles(id,full_name) values
  ('00000000-0000-0000-0000-000000000001','Manager'),
  ('00000000-0000-0000-0000-000000000002','Site Manager'),
  ('00000000-0000-0000-0000-000000000004','Other Manager');
insert into public.agencies(id,name) values
  ('10000000-0000-0000-0000-000000000001','Agency A'),
  ('10000000-0000-0000-0000-000000000002','Agency B');
insert into public.client_companies(id,agency_id,name) values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Client A'),
  ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Client B');
insert into public.sites(id,agency_id,client_company_id,name) values
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','A1'),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','A2'),
  ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','B1');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
  ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null,'supervisor'),
  ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','supervisor'),
  ('00000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000002',null,'supervisor');
select public.test_assert(not has_function_privilege('authenticated',
  'public.finish_user_invite(uuid,uuid,text,uuid,uuid,text,text)','EXECUTE'),
  'client cannot directly assign accounts');
select public.test_assert(not has_function_privilege('anon',
  'public.list_managed_users(uuid,uuid)','EXECUTE'), 'anonymous caller cannot list user emails');
set local role service_role;
select public.test_assert(public.can_invite_user(
  '00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null,'supervisor'),
  'agency Supervisor may invite another Supervisor');
select public.test_assert(not public.can_invite_user(
  '00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',null,'supervisor'),
  'site Supervisor cannot invite agency-wide Supervisor');
select public.test_assert(not public.can_invite_user(
  '00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000002','personnel'), 'site Supervisor cannot invite to another site');
select public.test_assert(not public.can_invite_user(
  '00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000003','personnel'), 'foreign-agency site rejected');
select public.test_assert(public.find_invite_target(
  '00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001','personnel',' WORKER@example.test ')
  ='00000000-0000-0000-0000-000000000003','authorized duplicate lookup is case insensitive');
select public.test_assert(public.finish_user_invite(
  '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','worker@example.test',
  '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','personnel','Worker')='assigned',
  'invitation grants scoped Personnel role');
select public.test_assert((select count(*)=1 from public.personnel_assignments where user_id='00000000-0000-0000-0000-000000000003'),
  'invitation creates personnel workplace assignment');
select public.test_assert(exists(select 1 from public.audit_events where actor_id='00000000-0000-0000-0000-000000000001'
  and entity_type='role_assignments' and action='insert'), 'trusted invitation records real actor');
select public.test_assert(public.finish_user_invite(
  '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','worker@example.test',
  '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','personnel','Worker')='already_assigned',
  'duplicate invitation is idempotent');
select public.test_assert(public.finish_user_invite(
  '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000005','invited@example.test',
  '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','personnel','Invited')='assigned',
  'site Supervisor may invite Personnel only at assigned site');
select public.test_assert((select count(*)=2 from public.list_managed_users(
  '00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001')),
  'site Supervisor list contains only scoped Personnel');
select public.test_assert((select count(*)=4 from public.list_managed_users(
  '00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001')),
  'agency Supervisor list includes its Supervisors and Personnel');
do $$ begin
  begin
    perform public.finish_user_invite('00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000003','worker@example.test',
      '10000000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000003','personnel','Worker');
    raise exception 'FAIL: cross-agency invitation succeeded';
  exception when insufficient_privilege then raise notice 'PASS: cross-agency invitation denied'; end;
  begin
    perform public.set_personnel_access('00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000002',false);
    raise exception 'FAIL: site Supervisor suspended another site';
  exception when insufficient_privilege then raise notice 'PASS: cross-site suspension denied'; end;
  begin
    perform public.set_personnel_access('00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',false);
    raise exception 'FAIL: Supervisor suspension succeeded';
  exception when insufficient_privilege then raise notice 'PASS: Supervisor cannot suspend another Supervisor'; end;
end $$;
select public.set_personnel_access('00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',false);
select public.test_assert((select not is_active from public.role_assignments where user_id='00000000-0000-0000-0000-000000000003'),
  'suspension revokes assigned role');
select public.test_assert(exists(select 1 from public.audit_events where actor_id='00000000-0000-0000-0000-000000000002'
  and entity_type='role_assignments' and action='update'
  and before_data->>'is_active'='true' and after_data->>'is_active'='false'), 'suspension preserves actor and before/after values');
select public.set_personnel_access('00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',true);
select public.test_assert((select is_active from public.role_assignments where user_id='00000000-0000-0000-0000-000000000003'),
  'reactivation restores assigned role');
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000005","is_anonymous":false}',true);
set local role authenticated;
select public.test_assert(public.needs_password_setup(), 'new invited Personnel must choose first password');
reset role;
rollback;
