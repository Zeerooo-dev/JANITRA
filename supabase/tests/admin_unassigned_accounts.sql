begin;
create function public.unassigned_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
do $$
declare
 a uuid:='00000000-0000-0000-0000-000000001101';
 s uuid:='00000000-0000-0000-0000-000000001102';
 p uuid:='00000000-0000-0000-0000-000000001103';
 u uuid:='00000000-0000-0000-0000-000000001104';
 op uuid:='80000000-0000-0000-0000-000000001104';
 ag uuid:='10000000-0000-0000-0000-000000001101';
 site uuid:='30000000-0000-0000-0000-000000001101';
 r jsonb; claim jsonb; op2 uuid:=gen_random_uuid(); user2 uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,email_confirmed_at) values(a,'admin-unassigned@test.invalid',now()),(s,'super-unassigned@test.invalid',now()),(p,'person-unassigned@test.invalid',now());
 insert into public.profiles(id,full_name) values(a,'Admin unassigned');
 insert into public.role_assignments(user_id,role,agency_id) values(a,'admin',null);
 perform public.unassigned_assert(public.can_invite_user(a,null,null,'supervisor'),'Admin can invite Supervisor without company');
 perform public.unassigned_assert(public.can_invite_user(a,null,null,'personnel'),'Admin can invite Personnel without company');
 perform public.unassigned_assert(public.finish_supervisor_invite(a,a,s,'super-unassigned@test.invalid',null,null,'Pending Supervisor')='unassigned','Supervisor invitation creates unassigned account');
 perform public.unassigned_assert(public.finish_user_invite(a,p,'person-unassigned@test.invalid',null,null,'personnel','Pending Personnel')='unassigned','Personnel email invitation creates unassigned account');
 perform public.unassigned_assert(public.finish_user_invite(a,p,'person-unassigned@test.invalid',null,null,'personnel','Pending Personnel')='unassigned','unassigned invitation retry is idempotent');
 perform public.unassigned_assert(not public.actor_session_valid(s,s) and not public.actor_session_valid(p,p),'unassigned accounts have no protected access');
 perform public.unassigned_assert(not janitra_private.is_company_wide_supervisor(s),'unassigned Supervisor has no Company-Wide authority');
 perform public.unassigned_assert(not public.can_invite_user(s,null,null,'personnel'),'unassigned Supervisor cannot provision unassigned people');
 begin
  update public.role_assignments set is_active=true where user_id=s;
  raise exception 'FAIL: unassigned role activated';
 exception when check_violation then raise notice 'PASS: null-scope activation fails closed'; end;
 perform public.unassigned_assert(jsonb_array_length(public.owner_list_accounts(a,a))>=2,'Admin lists unassigned accounts');
 perform public.unassigned_assert(exists(select 1 from jsonb_array_elements(public.owner_list_accounts(a,a)) x where x->>'user_id'=p::text and (x->>'is_unassigned')::boolean),'directory marks unassigned rows explicitly');
 perform public.unassigned_assert(public.can_delete_account(a,a,p),'Admin can delete unassigned Personnel');
 update auth.users set encrypted_password='' where id=s;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',s,'session_id',s,'is_anonymous',false)::text,true);
 perform public.unassigned_assert(public.needs_password_setup(),'unassigned email invite still requires password setup');
 update auth.users set encrypted_password='test-only' where id=s;

 r:=public.personnel_identity_command(a,a,'reserve',jsonb_build_object('request_id',op,'username','pending1104','full_name','Pending Username','agency_id',null,'site_id',null));
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values(u,r->>'login_email',now(),jsonb_build_object('janitra_provisioning_id',op));
 perform public.personnel_identity_command(a,a,'finish_provision',jsonb_build_object('request_id',op,'user_id',u,'agency_id',null,'site_id',null));
 perform public.personnel_identity_command(a,a,'issue_grant',jsonb_build_object('user_id',u,'agency_id',null,'site_id',null,'purpose','setup','digest',repeat('a',64)));
 update janitra_private.account_setup_grants set expires_at=now()-interval '1 second' where user_id=u;
 perform public.unassigned_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','pending1104','digest',repeat('a',64)))='{}','expired unassigned setup code is denied');
 perform public.personnel_identity_command(a,a,'issue_grant',jsonb_build_object('user_id',u,'agency_id',null,'site_id',null,'purpose','setup','digest',repeat('b',64)));
 delete from auth.sessions where user_id=a;
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','pending1104','digest',repeat('b',64)));
 perform public.unassigned_assert(claim?'claim_id','unassigned setup works after Admin signs out');
 perform public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 perform public.unassigned_assert(not public.actor_session_valid(u,u),'password setup does not activate a null-scope role');
 perform public.unassigned_assert(public.personnel_identity_command(null,null,'login_lookup',jsonb_build_object('identifier','pending1104'))->>'user_id'=u::text,'unassigned username can authenticate after setup');
 -- Setup invalidates existing sessions; a fresh session remains authorization-free.
 insert into auth.sessions(id,user_id) values(gen_random_uuid(),u);
 perform public.unassigned_assert(public.actor_session_state(u,(select id from auth.sessions where user_id=u and id<>u limit 1))='unassigned','fresh pending login is distinguished from revoked access');
 insert into auth.sessions(id,user_id) values(a,a);
 insert into public.agencies(id,name) values(ag,'Assignment test company');
 insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000001101',ag,'Client');
 insert into public.sites(id,agency_id,client_company_id,name) values(site,ag,'20000000-0000-0000-0000-000000001101','Workplace');
 perform public.assign_unassigned_personnel(a,a,u,ag,site);
 perform public.unassigned_assert(exists(select 1 from public.role_assignments where user_id=u and agency_id=ag and site_id=site and is_active),'Admin assigns completed username account');
 perform public.manage_supervisor(a,a,s,ag,null,true,'Assigned Supervisor');
 insert into auth.sessions(id,user_id) values(s,s);
 perform public.unassigned_assert(not exists(select 1 from public.role_assignments where user_id=s and agency_id is null),'Supervisor assignment removes unassigned placeholder');
 perform public.unassigned_assert(not public.can_invite_user(s,null,null,'personnel'),'Company-Wide Supervisor cannot provision null-scope accounts');
 perform public.unassigned_assert(not exists(select 1 from jsonb_array_elements(public.owner_list_accounts(s,s)) x where (x->>'user_id')::uuid=p),'Company-Wide directory hides unassigned identities');
 begin
  perform public.assign_unassigned_personnel(s,s,p,ag,site);
  raise exception 'FAIL: Supervisor assigned unassigned account';
 exception when insufficient_privilege then raise notice 'PASS: only Admin assigns unassigned Personnel'; end;
 perform public.assign_unassigned_personnel(a,a,p,ag,site);
 perform public.unassigned_assert(exists(select 1 from public.personnel_assignments where user_id=p and site_id=site and is_active),'email Personnel assignment remains supported');
 r:=public.personnel_identity_command(s,s,'reserve',jsonb_build_object('request_id',gen_random_uuid(),'username','scoped1105','full_name','Scoped reserve','agency_id',ag,'site_id',site));
 perform public.unassigned_assert(r?'operation_id','existing scoped Supervisor username creation remains supported');
 r:=public.personnel_identity_command(a,a,'reserve',jsonb_build_object('request_id',op2,'username','pending1106','full_name','Assign before setup','agency_id',null,'site_id',null));
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values(user2,r->>'login_email',now(),jsonb_build_object('janitra_provisioning_id',op2));
 perform public.personnel_identity_command(a,a,'finish_provision',jsonb_build_object('request_id',op2,'user_id',user2,'agency_id',null,'site_id',null));
 perform public.personnel_identity_command(a,a,'issue_grant',jsonb_build_object('user_id',user2,'agency_id',null,'site_id',null,'purpose','setup','digest',repeat('c',64)));
 perform public.assign_unassigned_personnel(a,a,user2,ag,site);
 perform public.unassigned_assert(not exists(select 1 from public.role_assignments where user_id=user2 and is_active),'assignment cannot bypass mandatory password setup');
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','pending1106','digest',repeat('c',64)));
 perform public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
 perform public.unassigned_assert(exists(select 1 from public.role_assignments where user_id=user2 and agency_id=ag and site_id=site and is_active),'existing setup code activates only the later authorized workplace');
end $$;
rollback;
