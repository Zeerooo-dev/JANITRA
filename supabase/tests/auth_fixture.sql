-- Isolated PostgreSQL only: emulate the Supabase roles and request claims.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz,
  encrypted_password text default 'test-fixture-password-hash', raw_app_meta_data jsonb not null default '{}'::jsonb,
  invited_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade,not_after timestamptz);
create function auth.test_session() returns trigger language plpgsql as $$
begin insert into auth.sessions(id,user_id) values(new.id,new.id);return new;end;$$;
create trigger fixture_session after insert on auth.users for each row execute function auth.test_session();
create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'sub')::uuid;
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select jsonb_build_object('session_id',auth.uid()) || coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$$;
grant usage on schema auth, public to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
