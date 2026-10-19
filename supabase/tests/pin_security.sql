\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean,label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %',label; end if;
  raise notice 'PASS: %',label;
end;
$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000001','manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000002','site-manager@example.test',now()),
 ('00000000-0000-0000-0000-000000000003','worker@example.test',now());
insert into public.profiles(id,full_name) select id,email from auth.users;
insert into public.agencies(id,name) values
 ('10000000-0000-0000-0000-000000000001','Agency A'),
 ('10000000-0000-0000-0000-000000000002','Agency B');
insert into public.client_companies(id,agency_id,name) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Client A'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Client B');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','A1'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','B1');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','supervisor'),
 ('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','personnel');
select public.test_assert(not has_function_privilege('authenticated',
 'public.set_pin_credential(uuid,uuid,text,uuid,uuid,text)','EXECUTE'), 'client cannot set PIN digests directly');
select public.test_assert(not has_function_privilege('service_role',
 'janitra_private.verify_pin(uuid,text,uuid,uuid,text)','EXECUTE'), 'no standalone service/client PIN verification API');
select public.test_assert(not has_table_privilege('authenticated',
 'janitra_private.employee_pin_credentials','SELECT'), 'client cannot retrieve Employee PIN hashes');
select public.test_assert(not has_table_privilege('service_role',
 'janitra_private.employee_pin_credentials','SELECT'), 'Edge service role cannot retrieve raw PIN hashes');

set local role service_role;
select public.test_assert(public.can_manage_pin(
 '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','employee',
 '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 'site Supervisor can issue PIN to scoped Personnel');
select public.test_assert(not public.can_manage_pin(
 '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','supervisor',
 '10000000-0000-0000-0000-000000000001',null), 'Supervisor cannot reset another Supervisor PIN');
select public.test_assert((public.pin_status(
 '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','employee',
 '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001')->>'configured')::boolean=false,
 'new PIN status is not configured');
select public.set_pin_credential(
 '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','employee',
 '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',repeat('a',64));
select public.set_pin_credential(
 '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','supervisor',
 '10000000-0000-0000-0000-000000000001',null,repeat('a',64));
select public.test_assert((public.pin_status(
 '00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','employee',
 '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001')->>'configured')::boolean,
 'PIN status returns configuration metadata');
reset role;

do $$
declare worker uuid:='00000000-0000-0000-0000-000000000003';
 manager uuid:='00000000-0000-0000-0000-000000000001';
 agency uuid:='10000000-0000-0000-0000-000000000001';
 site uuid:='30000000-0000-0000-0000-000000000001'; result text;
begin
 perform public.test_assert((select pin_hash like '$2a$12$%' from janitra_private.employee_pin_credentials where user_id=worker),
  'Employee digest uses salted bcrypt cost 12');
 perform public.test_assert((select e.pin_hash<>s.pin_hash from janitra_private.employee_pin_credentials e
  cross join janitra_private.supervisor_pin_credentials s), 'same digest receives different random salts');
 perform public.test_assert(not exists(select 1 from public.audit_events where entity_type like '%pin_credentials'
  and (before_data::text like '%pin_hash%' or after_data::text like '%pin_hash%' or after_data::text like '%'||repeat('a',64)||'%')),
  'PIN audit contains metadata only, never hash or digest');
 perform public.test_assert(exists(select 1 from public.audit_events where entity_type='employee_pin_credentials'
  and actor_id='00000000-0000-0000-0000-000000000002'), 'issuance audit retains Supervisor actor');
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('a',64))='verified',
  'valid scoped Employee digest verifies internally');
 perform public.test_assert(janitra_private.verify_pin(worker,'supervisor',agency,site,repeat('a',64))='denied',
  'Personnel cannot use Supervisor PIN purpose');
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,
  '30000000-0000-0000-0000-000000000002',repeat('a',64))='denied', 'cross-agency verification denied');
 for i in 1..4 loop
  result:=janitra_private.verify_pin(worker,'employee',agency,site,repeat('b',64));
 end loop;
 perform public.test_assert(result='incorrect', 'four failed attempts remain restricted to account');
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('b',64))='locked',
  'fifth failed attempt locks for fifteen minutes');
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('a',64))='locked',
  'correct PIN cannot bypass a current lock');
 perform public.test_assert((select failed_attempts=5 and locked_until>clock_timestamp()+interval '14 minutes'
  from janitra_private.employee_pin_credentials where user_id=worker), 'locked attempts do not extend lock or increase counter');
 perform public.test_assert(janitra_private.verify_pin(manager,'supervisor',agency,site,repeat('a',64))='verified',
  'Employee lock does not lock another account or purpose');
 update janitra_private.employee_pin_credentials set locked_until=clock_timestamp()-interval '1 second' where user_id=worker;
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('a',64))='verified',
  'expired lock permits verification');
 perform public.test_assert((select failed_attempts=0 and locked_until is null
  from janitra_private.employee_pin_credentials where user_id=worker), 'successful verification clears failed-attempt state');
 perform public.set_pin_credential(manager,worker,'employee',agency,site,repeat('c',64));
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('a',64))='incorrect',
  'reset invalidates previous PIN digest');
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('c',64))='verified',
  'reset digest verifies');
 update public.role_assignments set is_active=false where user_id=worker;
 perform public.test_assert(janitra_private.verify_pin(worker,'employee',agency,site,repeat('c',64))='denied',
  'suspended workplace role cannot verify');
 update public.role_assignments set is_active=true where user_id=worker;
 insert into public.role_assignments(user_id,agency_id,site_id,role) values(worker,
  '10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','personnel');
 perform public.test_assert(not public.can_manage_pin(manager,worker,'employee',agency,site),
  'partial manager cannot reset global PIN affecting another agency');
 perform public.test_assert((public.pin_status(manager,worker,'employee',agency,site)->>'can_reset')::boolean=false,
  'scoped metadata explains unavailable multiagency reset');
 begin
  perform public.set_pin_credential(manager,worker,'employee',agency,site,repeat('d',64));
  raise exception 'FAIL: cross-agency PIN reset succeeded';
 exception when insufficient_privilege then raise notice 'PASS: unauthorized global PIN reset denied'; end;
end $$;
set local role authenticated;
do $$ begin
 begin
  perform janitra_private.verify_pin('00000000-0000-0000-0000-000000000003','employee',
   '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',repeat('c',64));
  raise exception 'FAIL: client verifier call succeeded';
 exception when insufficient_privilege then raise notice 'PASS: authenticated client cannot call internal verifier'; end;
end $$;
reset role;
\if :{?keep_pin_fixture}
commit;
\else
rollback;
\endif
