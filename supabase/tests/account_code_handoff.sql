\set ON_ERROR_STOP on
begin;
create function public.handoff_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000000011','issuer@test.invalid',now());
insert into auth.users(id,email,invited_at) values('00000000-0000-0000-0000-000000000012','invited@test.invalid',now());
insert into public.profiles(id,full_name) values('00000000-0000-0000-0000-000000000011','Issuer'),('00000000-0000-0000-0000-000000000012','Invited');
insert into public.agencies(id,name) values('10000000-0000-0000-0000-000000000011','Agency');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','Client');
insert into public.sites(id,agency_id,client_company_id,name) values('30000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011','Site');
insert into public.role_assignments(user_id,agency_id,site_id,role) values
 ('00000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011',null,'supervisor'),
 ('00000000-0000-0000-0000-000000000012','10000000-0000-0000-0000-000000000011','30000000-0000-0000-0000-000000000011','personnel');
do $$
declare manager uuid:='00000000-0000-0000-0000-000000000011'; worker uuid:='00000000-0000-0000-0000-000000000012';
 agency uuid:='10000000-0000-0000-0000-000000000011'; site uuid:='30000000-0000-0000-0000-000000000011'; args jsonb; claim jsonb;
begin
 args:=jsonb_build_object('agency_id',agency,'site_id',site,'user_id',worker,'purpose','recovery','reason','Verified in person for handoff','digest',repeat('a',64));
 perform public.personnel_identity_command(manager,manager,'issue_grant',args);
 delete from auth.sessions where user_id=manager;
 perform public.handoff_assert(not public.actor_session_valid(manager,manager),'issuer session really ended');
 update janitra_private.account_setup_grants set expires_at=clock_timestamp()-interval '1 second' where user_id=worker;
 perform public.handoff_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','invited@test.invalid','digest',repeat('a',64)))='{}','expired handoff denied');
 update janitra_private.account_setup_grants set expires_at=clock_timestamp()+interval '30 minutes' where user_id=worker;
 update public.profiles set is_active=false where id=manager;
 perform public.handoff_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','invited@test.invalid','digest',repeat('a',64)))='{}','suspended issuer denied');
 update public.profiles set is_active=true where id=manager;
 update public.role_assignments set is_active=false where user_id=manager;
 perform public.handoff_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','invited@test.invalid','digest',repeat('a',64)))='{}','revoked issuer scope denied');
 update public.role_assignments set is_active=true where user_id=manager;
 claim:=public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','invited@test.invalid','digest',repeat('a',64)));
 perform public.handoff_assert(claim ? 'claim_id' and claim->>'confirm_email'='true','signed-out issuer permits invited account handoff');
 update public.role_assignments set is_active=false where user_id=manager;
 begin
  perform public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'));
  raise exception 'FAIL: authority lost during Auth accepted';
 exception when insufficient_privilege then raise notice 'PASS: authority rechecked after Auth'; end;
 update public.role_assignments set is_active=true where user_id=manager;
 update auth.users set email_confirmed_at=now() where id=worker;
 perform public.handoff_assert(public.personnel_identity_command(null,null,'finish_grant',jsonb_build_object('claim_id',claim->>'claim_id'))->>'completed'='true','setup finishes after issuing session ended');
 perform public.handoff_assert(public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','invited@test.invalid','digest',repeat('a',64)))='{}','consumed handoff cannot be replayed');
end $$;
rollback;
