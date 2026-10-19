\set ON_ERROR_STOP on
begin;
create function public.creation_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at)
 select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'creation-'||n||'@test.invalid',now() from generate_series(1011,1014) n;
insert into public.profiles(id,full_name) select id,email from auth.users where email like 'creation-%';
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000001011','Original creation company');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000001011','10000000-0000-0000-0000-000000001011','Original client');
insert into public.sites(id,agency_id,client_company_id,name)
 values('30000000-0000-0000-0000-000000001011','10000000-0000-0000-0000-000000001011','20000000-0000-0000-0000-000000001011','Original site');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000001011',null,null,'admin'),
 ('00000000-0000-0000-0000-000000001012','10000000-0000-0000-0000-000000001011',null,'supervisor'),
 ('00000000-0000-0000-0000-000000001013','10000000-0000-0000-0000-000000001011','30000000-0000-0000-0000-000000001011','supervisor'),
 ('00000000-0000-0000-0000-000000001014','10000000-0000-0000-0000-000000001011','30000000-0000-0000-0000-000000001011','personnel');
select public.creation_assert(not has_function_privilege('anon','public.create_manpower_agency(uuid,text,uuid)','execute'),'anonymous client cannot create agencies');
select public.creation_assert(not has_function_privilege('authenticated','public.create_manpower_agency(uuid,text,uuid)','execute'),'client cannot forge agency creator/session');
select public.creation_assert(has_function_privilege('service_role','public.create_manpower_agency(uuid,text,uuid)','execute'),'verified backend can invoke agency creation');
set local role service_role;
select set_config('test.created_agency',public.create_manpower_agency('00000000-0000-0000-0000-000000001012','  LSERVE creation fixture  ','00000000-0000-0000-0000-000000001012')::text,true);
reset role;
do $$
declare a uuid:='00000000-0000-0000-0000-000000001011'; wide uuid:='00000000-0000-0000-0000-000000001012';
 scoped uuid:='00000000-0000-0000-0000-000000001013'; personnel uuid:='00000000-0000-0000-0000-000000001014';
 agency uuid:=current_setting('test.created_agency')::uuid; bad_name text; before_count integer;
begin
 perform public.creation_assert(exists(select 1 from public.agencies where id=agency and name='LSERVE creation fixture'),'Company-Wide creates a trimmed manpower agency');
 perform public.creation_assert(exists(select 1 from public.audit_events where entity_type='agencies' and entity_id=agency and actor_id=wide and action='insert'),'agency creation retains verified creator audit history');
 perform public.creation_assert((select count(*)=1 from public.role_assignments where user_id=wide),'agency creation does not add roles or change affiliation');
 perform public.creation_assert(not public.owner_account_access(wide,wide),'Company-Wide creation does not grant Admin authority');
 perform public.creation_assert(janitra_private.manager_has_scope(wide,agency,null),'creator immediately manages the new company');
 perform public.creation_assert(not public.can_invite_user(wide,agency,null,'supervisor'),'agency creator still cannot invite Supervisors');
 perform public.creation_assert(public.create_manpower_agency(a,'Admin creation fixture',a) is not null,'Admin retains agency creation');
 select count(*) into before_count from public.agencies;
 begin perform public.create_manpower_agency(scoped,'Forbidden scoped agency',scoped); raise exception 'FAIL: site-specific created agency';
 exception when insufficient_privilege then raise notice 'PASS: site-specific Supervisor cannot create agencies'; end;
 begin perform public.create_manpower_agency(personnel,'Forbidden Personnel agency',personnel); raise exception 'FAIL: Personnel created agency';
 exception when insufficient_privilege then raise notice 'PASS: Personnel cannot create agencies'; end;
 foreach bad_name in array array[null,'','   ',repeat('a',201)] loop
  begin perform public.create_manpower_agency(wide,bad_name,wide); raise exception 'FAIL: invalid company name accepted';
  exception when invalid_parameter_value then raise notice 'PASS: invalid company name rejected'; end;
 end loop;
 begin perform public.create_manpower_agency(wide,'Forged session company',a); raise exception 'FAIL: forged session created agency';
 exception when insufficient_privilege then raise notice 'PASS: another account session cannot authorize creation'; end;
 update public.profiles set is_active=false where id=wide;
 begin perform public.create_manpower_agency(wide,'Suspended company',wide); raise exception 'FAIL: suspended creator retained access';
 exception when insufficient_privilege then raise notice 'PASS: suspended Company-Wide account cannot create agencies'; end;
 update public.profiles set is_active=true where id=wide;
 update public.role_assignments set is_active=false where user_id=wide;
 begin perform public.create_manpower_agency(wide,'Revoked company',wide); raise exception 'FAIL: revoked creator retained access';
 exception when insufficient_privilege then raise notice 'PASS: revoked Company-Wide role cannot create agencies'; end;
 update public.role_assignments set is_active=true where user_id=wide;
 update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=wide;
 begin perform public.create_manpower_agency(wide,'Expired company',wide); raise exception 'FAIL: expired session created agency';
 exception when insufficient_privilege then raise notice 'PASS: expired session cannot create agencies'; end;
 update auth.sessions set not_after=null where id=wide;
 delete from auth.sessions where id=wide;
 begin perform public.create_manpower_agency(wide,'Signed out company',wide); raise exception 'FAIL: signed-out creator retained access';
 exception when insufficient_privilege then raise notice 'PASS: signed-out Company-Wide account cannot create agencies'; end;
 insert into auth.sessions(id,user_id) values(wide,wide);
 perform public.creation_assert((select count(*)=before_count from public.agencies),'all rejected creations leave no agency records');
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000001012","role":"authenticated"}',true);
select public.creation_assert(exists(select 1 from public.agencies where id=current_setting('test.created_agency')::uuid),'Company-Wide company selector can read new agency through RLS');
insert into public.client_companies(agency_id,name) values(current_setting('test.created_agency')::uuid,'New company client');
insert into public.sites(agency_id,client_company_id,name)
 select agency_id,id,'New company workplace' from public.client_companies where agency_id=current_setting('test.created_agency')::uuid;
select public.creation_assert(exists(select 1 from public.sites where agency_id=current_setting('test.created_agency')::uuid),'Company-Wide can add workplaces within new company through RLS');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000001013","role":"authenticated"}',true);
select public.creation_assert(not exists(select 1 from public.agencies where id=current_setting('test.created_agency')::uuid),'new company does not expand Site-Specific access');
rollback;
