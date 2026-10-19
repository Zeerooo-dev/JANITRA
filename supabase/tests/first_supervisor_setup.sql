\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %',label; end if;
  raise notice 'PASS: %',label;
end;
$$;
insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001','first@example.test',now()),
  ('00000000-0000-0000-0000-000000000002','attacker@example.test',now()),
  ('00000000-0000-0000-0000-000000000003','unverified@example.test',null);
insert into janitra_private.supervisor_bootstrap_grants(user_id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000003');
select public.test_assert(not has_function_privilege('anon','public.setup_manpower_company(text,text)','EXECUTE'), 'public registration cannot call setup');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":false,"user_metadata":{"role":"supervisor"}}',true);
select public.test_assert(not public.needs_company_setup(),'unapproved account cannot see setup');
do $$ begin
  begin
    perform public.setup_manpower_company('Attacker Company','Attacker');
    raise exception 'FAIL: unapproved account completed setup';
  exception when insufficient_privilege then raise notice 'PASS: unapproved setup denied'; end;
  begin
    insert into janitra_private.supervisor_bootstrap_grants(user_id) values(auth.uid());
    raise exception 'FAIL: account granted itself setup';
  exception when insufficient_privilege then raise notice 'PASS: client cannot create bootstrap grants'; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000003","is_anonymous":false}',true);
select public.test_assert(not public.needs_company_setup(),'email verification required before setup');
do $$ begin
  begin
    perform public.setup_manpower_company('Unverified Company','Unverified');
    raise exception 'FAIL: unverified account completed setup';
  exception when insufficient_privilege then raise notice 'PASS: unverified setup denied'; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","is_anonymous":true}',true);
select public.test_assert(not public.needs_company_setup(),'anonymous session cannot access setup');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select public.test_assert(public.needs_company_setup(),'approved verified Supervisor can start setup');
reset role;
update auth.users set encrypted_password='' where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.test_assert(public.needs_password_setup(),'invited account must choose a password');
do $$ begin
  begin
    perform public.setup_manpower_company('My Manpower Company','First Supervisor');
    raise exception 'FAIL: passwordless invitation completed company setup';
  exception when insufficient_privilege then raise notice 'PASS: company setup requires password enrollment'; end;
end $$;
reset role;
update auth.users set encrypted_password='test-fixture-password-hash' where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.test_assert(not public.needs_password_setup(),'password enrollment clears the first-password requirement');
do $$ declare first_agency uuid; repeated_agency uuid; begin
  begin
    perform public.setup_manpower_company(' ','Supervisor');
    raise exception 'FAIL: empty company name accepted';
  exception when invalid_parameter_value then raise notice 'PASS: empty company name rejected'; end;
  first_agency := public.setup_manpower_company('  My Manpower Company  ','  First Supervisor  ');
  repeated_agency := public.setup_manpower_company('My Manpower Company','First Supervisor');
  perform public.test_assert(first_agency=repeated_agency,'repeated setup returns same agency');
  perform public.test_assert((select count(*)=1 from public.agencies),'setup creates exactly one agency');
  perform public.test_assert((select full_name='First Supervisor' from public.profiles where id=auth.uid()),'Supervisor profile uses entered name');
  perform public.test_assert(janitra_private.has_site_role(first_agency,null,array['supervisor']),'setup grants Supervisor within own agency');
  perform public.test_assert(not public.needs_company_setup(),'bootstrap grant consumed after setup');
  perform public.test_assert((select count(*)=0 from public.client_companies),'client name not invented');
  perform public.test_assert((select count(*)=0 from public.sites),'site name not invented');
  perform public.test_assert((select count(*)=2 from public.audit_events where actor_id=auth.uid()),'company and Supervisor grant are audited');
end $$;
reset role;
update public.profiles set is_active=false where id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
  begin
    perform public.setup_manpower_company('My Manpower Company','First Supervisor');
    raise exception 'FAIL: suspended Supervisor reused bootstrap';
  exception when insufficient_privilege then raise notice 'PASS: suspended account cannot reuse bootstrap'; end;
end $$;
reset role;
rollback;
