\set ON_ERROR_STOP on
begin;
create function public.directory_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at)
 select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'directory-'||n||'@test.invalid',now() from generate_series(981,987) n;
insert into public.profiles(id,full_name) select id,email from auth.users where email like 'directory-%';
insert into public.agencies(id,name) values
 ('10000000-0000-0000-0000-000000000981','Directory Agency A'),('10000000-0000-0000-0000-000000000982','Directory Agency B');
insert into public.client_companies(id,agency_id,name) values
 ('20000000-0000-0000-0000-000000000981','10000000-0000-0000-0000-000000000981','Client A'),
 ('20000000-0000-0000-0000-000000000982','10000000-0000-0000-0000-000000000982','Client B');
insert into public.sites(id,agency_id,client_company_id,name) values
 ('30000000-0000-0000-0000-000000000981','10000000-0000-0000-0000-000000000981','20000000-0000-0000-0000-000000000981','Site A'),
 ('30000000-0000-0000-0000-000000000982','10000000-0000-0000-0000-000000000982','20000000-0000-0000-0000-000000000982','Site B'),
 ('30000000-0000-0000-0000-000000000983','10000000-0000-0000-0000-000000000981','20000000-0000-0000-0000-000000000981','Site A2');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000981',null,null,'admin'),
 ('00000000-0000-0000-0000-000000000982','10000000-0000-0000-0000-000000000981',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000983','10000000-0000-0000-0000-000000000981','30000000-0000-0000-0000-000000000981','supervisor'),
 ('00000000-0000-0000-0000-000000000984','10000000-0000-0000-0000-000000000981','30000000-0000-0000-0000-000000000981','personnel'),
 ('00000000-0000-0000-0000-000000000985','10000000-0000-0000-0000-000000000982',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000986','10000000-0000-0000-0000-000000000982','30000000-0000-0000-0000-000000000982','personnel'),
 ('00000000-0000-0000-0000-000000000987','10000000-0000-0000-0000-000000000981','30000000-0000-0000-0000-000000000983','personnel');
insert into janitra_private.personnel_identities(id,user_id,username,login_email,contact_email,full_name,agency_id,site_id,created_by,state)
 values(gen_random_uuid(),'00000000-0000-0000-0000-000000000986','directory.person','directory-986@test.invalid','directory-986@test.invalid','Directory Personnel',
 '10000000-0000-0000-0000-000000000982','30000000-0000-0000-0000-000000000982','00000000-0000-0000-0000-000000000981','active');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000982","role":"authenticated"}',true);
select public.directory_assert(exists(select 1 from public.agencies where id='10000000-0000-0000-0000-000000000981'),'own agency remains readable through RLS');
select public.directory_assert(not exists(select 1 from public.agencies where id='10000000-0000-0000-0000-000000000982'),'agency table RLS is not broadened');
select public.directory_assert(not exists(select 1 from public.sites where id='30000000-0000-0000-0000-000000000982'),'site table RLS is not broadened');
reset role;
do $$
declare a uuid:='00000000-0000-0000-0000-000000000981'; wide uuid:='00000000-0000-0000-0000-000000000982';
 scoped uuid:='00000000-0000-0000-0000-000000000983'; own_p uuid:='00000000-0000-0000-0000-000000000984';
 other_s uuid:='00000000-0000-0000-0000-000000000985'; other_p uuid:='00000000-0000-0000-0000-000000000986';
 agency uuid:='10000000-0000-0000-0000-000000000981'; other_agency uuid:='10000000-0000-0000-0000-000000000982';
 site uuid:='30000000-0000-0000-0000-000000000981'; other_site uuid:='30000000-0000-0000-0000-000000000982';
 users jsonb;
begin
 users:=public.owner_list_accounts(wide,wide);
 perform public.directory_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=other_p::text),'agency-wide Supervisor sees other-agency Personnel');
 perform public.directory_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=other_s::text),'agency-wide Supervisor sees other-agency Supervisors');
 perform public.directory_assert(not exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=a::text),'Admin stays hidden from directory');
 perform public.directory_assert(not exists(select 1 from jsonb_array_elements(users) x where x->>'agency_id'=other_agency::text
  and (x->>'email' is not null or x->>'username' is not null or (x->>'can_delete')::boolean)),'foreign directory hides account identifiers and deletion permission');
 perform public.directory_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=own_p::text
  and x->>'email'='directory-984@test.invalid' and (x->>'can_delete')::boolean),'own Personnel management data remains available');
 users:=public.owner_list_accounts(scoped,scoped);
 perform public.directory_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=own_p::text),'site Supervisor still sees assigned Personnel');
 perform public.directory_assert(not exists(select 1 from jsonb_array_elements(users) x where x->>'agency_id'=other_agency::text),'site Supervisor cannot browse foreign agency');
 perform public.directory_assert(not exists(select 1 from jsonb_array_elements(users) x where x->>'site_id'='30000000-0000-0000-0000-000000000983'),'site Supervisor cannot browse unassigned site');
 perform public.directory_assert(jsonb_array_length(public.owner_list_accounts(own_p,own_p))=0,'Personnel has no people directory');
 perform public.directory_assert(not public.can_invite_user(wide,other_agency,other_site,'personnel'),'directory access cannot invite outside assigned agency');
 perform public.directory_assert(not public.can_delete_account(wide,wide,other_p),'directory access cannot delete foreign Personnel');
 perform public.directory_assert(not public.can_delete_account(wide,wide,other_s),'directory access cannot delete Supervisors');
 perform public.directory_assert(not janitra_private.pin_scope(wide,other_p,'employee',other_agency,other_site,true),'directory access cannot reset foreign PIN');
 begin
  perform public.edit_personnel(wide,wide,other_p,'Forbidden');
  raise exception 'FAIL: directory edited foreign Personnel';
 exception when insufficient_privilege then raise notice 'PASS: directory cannot edit foreign Personnel'; end;
 begin
  perform public.manage_supervisor(wide,wide,other_s,other_agency,null,true,'Forbidden');
  raise exception 'FAIL: directory edited Supervisor';
 exception when insufficient_privilege then raise notice 'PASS: directory cannot manage Supervisors'; end;
 users:=public.owner_list_accounts(a,a);
 perform public.directory_assert(exists(select 1 from jsonb_array_elements(users) x where x->>'user_id'=other_p::text
  and x->>'email'='directory-986@test.invalid' and x->>'username'='directory.person'),'Admin directory and account details preserved');
 update public.role_assignments set is_active=false where user_id=wide;
 insert into public.role_assignments(user_id,agency_id,site_id,role) values(wide,agency,site,'supervisor');
 perform public.directory_assert(not exists(select 1 from jsonb_array_elements(public.owner_list_accounts(wide,wide)) x
  where x->>'agency_id'=other_agency::text),'revoked agency-wide scope immediately loses cross-agency visibility');
 update public.profiles set is_active=false where id=wide;
 begin
  perform public.owner_list_accounts(wide,wide);
  raise exception 'FAIL: suspended actor read directory';
 exception when insufficient_privilege then raise notice 'PASS: suspended actor denied directory'; end;
 delete from auth.sessions where user_id=scoped;
 begin
  perform public.owner_list_accounts(scoped,scoped);
  raise exception 'FAIL: expired session read directory';
 exception when insufficient_privilege then raise notice 'PASS: expired session denied directory'; end;
end $$;
set local role authenticated;
select public.directory_assert(not has_function_privilege('authenticated','public.owner_list_accounts(uuid,uuid)','execute'),'directory RPC remains service-only');
select public.directory_assert(not has_function_privilege('anon','public.owner_list_accounts(uuid,uuid)','execute'),'anonymous directory calls denied');
reset role;
rollback;
