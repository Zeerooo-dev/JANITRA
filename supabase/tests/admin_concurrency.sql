insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-000000000961','admin-race1@test.invalid',now()),
 ('00000000-0000-0000-0000-000000000962','admin-race2@test.invalid',now());
insert into public.profiles(id,full_name) values
 ('00000000-0000-0000-0000-000000000961','Admin One'),('00000000-0000-0000-0000-000000000962','Admin Two');
insert into public.role_assignments(user_id,role) values
 ('00000000-0000-0000-0000-000000000961','admin'),('00000000-0000-0000-0000-000000000962','admin');
create function public.test_suspend_admin(target uuid) returns boolean language plpgsql as $$
begin
 update public.profiles set is_active=false where id=target;
 return true;
exception when insufficient_privilege then return false;
end $$;
