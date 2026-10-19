\set ON_ERROR_STOP on
begin;
create function public.test_assert(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %', label; end if;
  raise notice 'PASS: %', label;
end;
$$;
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', 'super-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000002', 'person-a@example.test', now()),
  ('00000000-0000-0000-0000-000000000003', 'super-b@example.test', now()),
  ('00000000-0000-0000-0000-000000000004', 'site-super@example.test', now()),
  ('00000000-0000-0000-0000-000000000005', 'suspended@example.test', now()),
  ('00000000-0000-0000-0000-000000000006', 'unassigned@example.test', now());
insert into public.profiles (id, full_name, is_active)
  select id, email, id <> '00000000-0000-0000-0000-000000000005' from auth.users;
insert into public.agencies (id, name) values
  ('10000000-0000-0000-0000-000000000001', 'Agency A'),
  ('10000000-0000-0000-0000-000000000002', 'Agency B');
insert into public.client_companies (id, agency_id, name) values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001', 'Client A'),
  ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002', 'Client B');
insert into public.sites (id, agency_id, client_company_id, name) values
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001', 'A1'),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001', 'A2'),
  ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002', 'B1');
insert into public.role_assignments(user_id, agency_id, site_id, role)
values
  ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001', null, 'supervisor'),
  ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'personnel'),
  ('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002', null, 'supervisor'),
  ('00000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'supervisor'),
  ('00000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'personnel');

select public.test_assert((select count(*) = 10 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','janitra_private') and c.relkind='r' and c.relrowsecurity
  and c.relname in ('profiles','agencies','client_companies','sites','service_contracts','role_assignments','personnel_assignments','audit_events','employee_pin_credentials','supervisor_pin_credentials')), 'all foundation tables have RLS');
select public.test_assert(not has_table_privilege('anon','public.profiles','SELECT'), 'anonymous Data API has no table grant');
select public.test_assert(not has_table_privilege('authenticated','janitra_private.employee_pin_credentials','SELECT'), 'Employee PIN hashes have no client grant');
select public.test_assert(not has_table_privilege('authenticated','janitra_private.supervisor_pin_credentials','SELECT'), 'Supervisor PIN hashes have no client grant');
select public.test_assert(not has_table_privilege('service_role','public.audit_events','UPDATE,DELETE,TRUNCATE'), 'audit history cannot be rewritten by API roles');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":false,"user_metadata":{"role":"supervisor"}}', true);
select public.test_assert((select count(*)=1 from public.sites), 'personnel reads assigned site only');
select public.test_assert((select count(*)=1 from public.profiles), 'personnel reads own profile only');
select public.test_assert((select count(*)=1 from public.agencies), 'personnel reads own agency only');
select public.test_assert((select count(*)=1 from public.client_companies), 'personnel reads assigned client only');
select public.test_assert((select count(*)=0 from public.audit_events), 'personnel cannot read organization audit');
select public.test_assert(not janitra_private.has_site_role('10000000-0000-0000-0000-000000000001',null,array['supervisor']), 'editable metadata cannot grant Supervisor role');
do $$ begin
  begin
    insert into public.role_assignments(user_id,agency_id,role) values(auth.uid(),'10000000-0000-0000-0000-000000000001','supervisor');
    raise exception 'FAIL: personnel promoted themselves';
  exception when insufficient_privilege then raise notice 'PASS: role escalation denied'; end;
  begin
    update public.profiles set is_active=false where id=auth.uid();
    raise exception 'FAIL: personnel modified account suspension';
  exception when insufficient_privilege then raise notice 'PASS: account suspension is backend-only'; end;
  begin
    insert into public.client_companies(agency_id,name) values('10000000-0000-0000-0000-000000000001','Unauthorized');
    raise exception 'FAIL: personnel created a client';
  exception when insufficient_privilege then raise notice 'PASS: personnel cannot create clients'; end;
  begin
    select pin_hash from janitra_private.employee_pin_credentials;
    raise exception 'FAIL: PIN hashes readable';
  exception when insufficient_privilege then raise notice 'PASS: direct PIN hash access denied'; end;
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","is_anonymous":false}', true);
select public.test_assert((select count(*)=2 from public.sites), 'Supervisor scope excludes other agency');
select public.test_assert((select count(*)=4 from public.profiles), 'Supervisor can view scoped suspended personnel');
update public.agencies set name='Agency A updated' where id='10000000-0000-0000-0000-000000000001';
select public.test_assert(exists(select 1 from public.audit_events where entity_type='agencies' and action='update'
  and actor_id=auth.uid() and before_data->>'name'='Agency A' and after_data->>'name'='Agency A updated'), 'writes record actor and before/after values');
do $$ declare changed integer; begin
  update public.agencies set name='Attacker' where id='10000000-0000-0000-0000-000000000002';
  get diagnostics changed=row_count;
  perform public.test_assert(changed=0,'cross-agency update denied');
  begin
    insert into public.sites(agency_id,client_company_id,name)
      values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','Invalid');
    raise exception 'FAIL: cross-agency foreign key accepted';
  exception when foreign_key_violation then raise notice 'PASS: cross-agency client/site relation denied'; end;
  begin
    delete from public.audit_events;
    raise exception 'FAIL: audit events deleted';
  exception when insufficient_privilege then raise notice 'PASS: audit deletion denied'; end;
end $$;

insert into public.client_companies(agency_id,name) values('10000000-0000-0000-0000-000000000001','New scoped client');
insert into public.sites(agency_id,client_company_id,name)
  select agency_id,id,'New scoped site' from public.client_companies where name='New scoped client';
update public.client_companies set name='Renamed scoped client' where name='New scoped client';
update public.sites set name='Renamed scoped site' where name='New scoped site';
select public.test_assert(exists(select 1 from public.client_companies where name='Renamed scoped client'), 'agency Supervisor can create and rename clients');
select public.test_assert(exists(select 1 from public.sites where name='Renamed scoped site'), 'agency Supervisor can create and rename workplaces');
select public.test_assert(exists(select 1 from public.audit_events where entity_type='sites' and action='update'
  and actor_id=auth.uid() and before_data->>'name'='New scoped site' and after_data->>'name'='Renamed scoped site'), 'workplace rename preserves audited actor and history');
update public.profiles set full_name='Updated Supervisor' where id=auth.uid();
select public.test_assert((select full_name='Updated Supervisor' from public.profiles where id=auth.uid()), 'Supervisor may update own display name');
do $$ begin
  begin
    insert into public.client_companies(agency_id,name) values('10000000-0000-0000-0000-000000000002','Wrong agency');
    raise exception 'FAIL: Supervisor created another agency client';
  exception when insufficient_privilege then raise notice 'PASS: cross-agency client creation denied'; end;
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000004","is_anonymous":false}', true);
select public.test_assert((select count(*)=1 from public.sites), 'site Supervisor cannot read other sites');
update public.sites set name='Site Supervisor edit' where id='30000000-0000-0000-0000-000000000001';
select public.test_assert((select name='Site Supervisor edit' from public.sites where id='30000000-0000-0000-0000-000000000001'), 'site Supervisor can rename assigned workplace');
do $$ begin
  begin
    insert into public.sites(agency_id,client_company_id,name) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Unauthorized site');
    raise exception 'FAIL: site Supervisor created a workplace';
  exception when insufficient_privilege then raise notice 'PASS: site Supervisor cannot create workplaces'; end;
end $$;

do $$ declare changed integer; begin
  update public.agencies set name='Site override';
  get diagnostics changed=row_count;
  perform public.test_assert(changed=0,'site Supervisor cannot modify whole agency');
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000005","is_anonymous":false}', true);
select public.test_assert((select count(*)=0 from public.sites), 'suspended account denied with existing JWT');
select public.test_assert((select count(*)=0 from public.profiles), 'suspended account cannot read profiles');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","is_anonymous":true}', true);
select public.test_assert((select count(*)=0 from public.sites), 'anonymous authenticated session denied');
select public.test_assert((select count(*)=0 from public.profiles), 'anonymous authenticated session cannot read profile');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","is_anonymous":false}', true);
select public.test_assert((select count(*)=0 from public.agencies), 'unassigned account has no agency access');
reset role;
select set_config('request.jwt.claims','{}',true);
update public.profiles set is_active=false where id='00000000-0000-0000-0000-000000000002';
select public.test_assert(exists(select 1 from public.audit_events where entity_type='profiles'
  and entity_id='00000000-0000-0000-0000-000000000002' and before_data->>'is_active'='true'
  and after_data->>'is_active'='false' and agency_id='10000000-0000-0000-0000-000000000001'), 'account suspension is audited within agency scope');
rollback;
