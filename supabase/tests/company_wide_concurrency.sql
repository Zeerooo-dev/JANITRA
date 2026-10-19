\set ON_ERROR_STOP on
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000001001','company-race@test.invalid',now());
insert into public.profiles(id,full_name) values('00000000-0000-0000-0000-000000001001','Company race fixture');
insert into public.agencies(id,name) values
 ('10000000-0000-0000-0000-000000001001','Race affiliation'),('10000000-0000-0000-0000-000000001002','Race foreign company');
insert into public.client_companies(id,agency_id,name) values('20000000-0000-0000-0000-000000001002','10000000-0000-0000-0000-000000001002','Race client');
insert into public.sites(id,agency_id,client_company_id,name)
 values('30000000-0000-0000-0000-000000001002','10000000-0000-0000-0000-000000001002','20000000-0000-0000-0000-000000001002','Race site');
insert into public.role_assignments(user_id,agency_id,role)
 values('00000000-0000-0000-0000-000000001001','10000000-0000-0000-0000-000000001001','supervisor');
create function public.test_company_scope_write(p_create boolean default false) returns text language plpgsql as $$
begin
 if p_create then
  perform public.create_manpower_agency('00000000-0000-0000-0000-000000001001','Revoked creation must not exist','00000000-0000-0000-0000-000000001001');
 else
 perform public.workflow_command('00000000-0000-0000-0000-000000001001','00000000-0000-0000-0000-000000001001','activity_save',
  '{"id":"40000000-0000-0000-0000-000000001001","request_id":"80000000-0000-0000-0000-000000001001","agency_id":"10000000-0000-0000-0000-000000001002","site_id":"30000000-0000-0000-0000-000000001002","name":"Must not be written"}'::jsonb);
 end if;
 return 'allowed';
exception when insufficient_privilege then return 'denied';
end $$;
