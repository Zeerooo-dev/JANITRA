begin;
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.personnel_identity_command(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(definition,'or not public.actor_session_valid(g.issued_by,g.issuer_session)')=0 then
  raise exception 'Unexpected identity command definition';
 end if;
 -- Redemption follows the grant expiry and current issuing authority, not the old login session.
 definition:=replace(definition,'or not public.actor_session_valid(g.issued_by,g.issuer_session)','');
 definition:=replace(definition,
  '''login_email'',i.login_email);',
  '''login_email'',i.login_email,''confirm_email'',exists(select 1 from auth.users u where u.id=i.user_id and u.email_confirmed_at is null and u.invited_at is not null));');
 execute definition;
end $$;
commit;
