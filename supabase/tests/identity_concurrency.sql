\set ON_ERROR_STOP on
begin;
-- Reuse the isolated workflow race's Supervisor, workplace and Personnel fixture.
insert into janitra_private.personnel_identities(id,user_id,username,login_email,full_name,agency_id,site_id,created_by,state)
values('98000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000902','race.person','race-worker@example.test','Race Personnel',
 '90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000901','active');
select public.personnel_identity_command('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000901','issue_grant',
 jsonb_build_object('agency_id','90000000-0000-0000-0000-000000000001','site_id','93000000-0000-0000-0000-000000000001',
 'user_id','00000000-0000-0000-0000-000000000902','purpose','recovery','reason','Concurrent recovery test','digest',repeat('f',64)));
commit;
