begin;

create schema janitra_private;
revoke all on schema janitra_private from public;
grant usage on schema janitra_private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null check (length(btrim(full_name)) between 1 and 200),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  created_at timestamptz not null default now()
);

create table public.client_companies (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 200),
  created_at timestamptz not null default now(),
  unique (id, agency_id),
  unique (agency_id, name)
);

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete restrict,
  client_company_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 200),
  created_at timestamptz not null default now(),
  foreign key (client_company_id, agency_id) references public.client_companies(id, agency_id) on delete restrict,
  unique (id, agency_id),
  unique (agency_id, client_company_id, name)
);

create table public.service_contracts (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null,
  site_id uuid not null,
  starts_on date not null,
  ends_on date,
  created_at timestamptz not null default now(),
  foreign key (site_id, agency_id) references public.sites(id, agency_id) on delete restrict,
  check (ends_on is null or ends_on >= starts_on)
);

create table public.role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  agency_id uuid not null references public.agencies(id) on delete restrict,
  site_id uuid,
  role text not null check (role in ('supervisor', 'personnel')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (site_id, agency_id) references public.sites(id, agency_id) on delete restrict,
  check (role = 'supervisor' or site_id is not null),
  unique nulls not distinct (user_id, agency_id, site_id)
);

create table public.personnel_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  agency_id uuid not null,
  site_id uuid not null,
  starts_on date not null,
  ends_on date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (site_id, agency_id) references public.sites(id, agency_id) on delete restrict,
  check (ends_on is null or ends_on >= starts_on),
  unique (user_id, site_id, starts_on)
);

create table janitra_private.employee_pin_credentials (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  pin_hash text not null check (pin_hash ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  changed_by uuid not null references public.profiles(id) on delete restrict,
  changed_at timestamptz not null default now()
);

create table janitra_private.supervisor_pin_credentials (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  pin_hash text not null check (pin_hash ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  changed_by uuid not null references public.profiles(id) on delete restrict,
  changed_at timestamptz not null default now()
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete restrict,
  agency_id uuid references public.agencies(id) on delete restrict,
  site_id uuid,
  entity_type text not null,
  entity_id uuid not null,
  action text not null check (action in ('insert', 'update', 'delete')),
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  foreign key (site_id, agency_id) references public.sites(id, agency_id) on delete restrict
);

create index client_companies_agency_idx on public.client_companies(agency_id);
create index sites_client_idx on public.sites(client_company_id, agency_id);
create index sites_agency_idx on public.sites(agency_id);
create index role_assignments_scope_idx on public.role_assignments(agency_id, site_id, user_id) where is_active;
create index service_contracts_scope_idx on public.service_contracts(agency_id, site_id);
create index personnel_assignments_scope_idx on public.personnel_assignments(agency_id, site_id, user_id);
create index audit_events_scope_idx on public.audit_events(agency_id, site_id, occurred_at desc);

-- Private lookups avoid recursive RLS while always deriving identity from the session.
create function janitra_private.has_site_role(target_agency uuid, target_site uuid, required_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
    and exists (
      select 1 from public.role_assignments r join public.profiles p on p.id = r.user_id
      where r.user_id = auth.uid() and p.is_active and r.is_active
        and r.agency_id = target_agency and r.role = any(required_roles)
        and (r.site_id is null or r.site_id = target_site)
    );
$$;

create function janitra_private.is_agency_member(target_agency uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
    and exists (
      select 1 from public.role_assignments r join public.profiles p on p.id = r.user_id
      where r.user_id = auth.uid() and p.is_active and r.is_active and r.agency_id = target_agency
    );
$$;

revoke all on function janitra_private.has_site_role(uuid, uuid, text[]) from public, anon;
revoke all on function janitra_private.is_agency_member(uuid) from public, anon;
grant execute on function janitra_private.has_site_role(uuid, uuid, text[]) to authenticated;
grant execute on function janitra_private.is_agency_member(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.agencies enable row level security;
alter table public.client_companies enable row level security;
alter table public.sites enable row level security;
alter table public.service_contracts enable row level security;
alter table public.role_assignments enable row level security;
alter table public.personnel_assignments enable row level security;
alter table public.audit_events enable row level security;
alter table janitra_private.employee_pin_credentials enable row level security;
alter table janitra_private.supervisor_pin_credentials enable row level security;

revoke all on public.profiles, public.agencies, public.client_companies, public.sites,
  public.service_contracts, public.role_assignments, public.personnel_assignments,
  public.audit_events from public, anon, authenticated;
revoke all on janitra_private.employee_pin_credentials, janitra_private.supervisor_pin_credentials
  from public, anon, authenticated;

grant usage on schema janitra_private to service_role;
grant all on public.profiles, public.agencies, public.client_companies, public.sites,
  public.service_contracts, public.role_assignments, public.personnel_assignments,
  janitra_private.employee_pin_credentials, janitra_private.supervisor_pin_credentials to service_role;
grant select, insert on public.audit_events to service_role;
revoke update, delete, truncate on public.audit_events from service_role;

grant select on public.profiles, public.agencies, public.client_companies, public.sites,
  public.service_contracts, public.role_assignments, public.personnel_assignments,
  public.audit_events to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant update (name) on public.agencies to authenticated;
grant insert (agency_id, name), update (name) on public.client_companies to authenticated;
grant insert (agency_id, client_company_id, name), update (name) on public.sites to authenticated;
grant insert (agency_id, site_id, starts_on, ends_on), update (starts_on, ends_on)
  on public.service_contracts to authenticated;
grant insert (user_id, agency_id, site_id, starts_on, ends_on, is_active),
  update (starts_on, ends_on, is_active) on public.personnel_assignments to authenticated;

create policy profiles_read on public.profiles for select to authenticated using (
  coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false and (
    (id = auth.uid() and is_active) or exists (
      select 1 from public.role_assignments r where r.user_id = profiles.id
        and janitra_private.has_site_role(r.agency_id, r.site_id, array['supervisor'])
    )
  )
);
create policy profiles_update_name on public.profiles for update to authenticated
  using (id = auth.uid() and is_active and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false)
  with check (id = auth.uid() and is_active and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false);

create policy agencies_read on public.agencies for select to authenticated
  using (janitra_private.is_agency_member(id));
create policy agencies_update on public.agencies for update to authenticated
  using (janitra_private.has_site_role(id, null, array['supervisor']))
  with check (janitra_private.has_site_role(id, null, array['supervisor']));

create policy client_companies_read on public.client_companies for select to authenticated using (
  janitra_private.has_site_role(agency_id, null, array['supervisor']) or exists (
    select 1 from public.sites s where s.client_company_id = client_companies.id
      and janitra_private.has_site_role(s.agency_id, s.id, array['supervisor','personnel'])
  )
);
create policy client_companies_insert on public.client_companies for insert to authenticated
  with check (janitra_private.has_site_role(agency_id, null, array['supervisor']));
create policy client_companies_update on public.client_companies for update to authenticated
  using (janitra_private.has_site_role(agency_id, null, array['supervisor']))
  with check (janitra_private.has_site_role(agency_id, null, array['supervisor']));

create policy sites_read on public.sites for select to authenticated
  using (janitra_private.has_site_role(agency_id, id, array['supervisor','personnel']));
create policy sites_insert on public.sites for insert to authenticated
  with check (janitra_private.has_site_role(agency_id, null, array['supervisor']));
create policy sites_update on public.sites for update to authenticated
  using (janitra_private.has_site_role(agency_id, id, array['supervisor']))
  with check (janitra_private.has_site_role(agency_id, id, array['supervisor']));

create policy service_contracts_read on public.service_contracts for select to authenticated
  using (janitra_private.has_site_role(agency_id, site_id, array['supervisor']));
create policy service_contracts_insert on public.service_contracts for insert to authenticated
  with check (janitra_private.has_site_role(agency_id, site_id, array['supervisor']));
create policy service_contracts_update on public.service_contracts for update to authenticated
  using (janitra_private.has_site_role(agency_id, site_id, array['supervisor']))
  with check (janitra_private.has_site_role(agency_id, site_id, array['supervisor']));

create policy role_assignments_read on public.role_assignments for select to authenticated using (
  (user_id = auth.uid() and janitra_private.is_agency_member(agency_id))
  or janitra_private.has_site_role(agency_id, site_id, array['supervisor'])
);

create policy personnel_assignments_read on public.personnel_assignments for select to authenticated
  using ((user_id = auth.uid() and janitra_private.has_site_role(agency_id, site_id, array['personnel']))
    or janitra_private.has_site_role(agency_id, site_id, array['supervisor']));
create policy personnel_assignments_insert on public.personnel_assignments for insert to authenticated
  with check (janitra_private.has_site_role(agency_id, site_id, array['supervisor']) and exists (
    select 1 from public.role_assignments r where r.user_id = personnel_assignments.user_id
      and r.agency_id = personnel_assignments.agency_id and r.site_id = personnel_assignments.site_id
      and r.role = 'personnel' and r.is_active
  ));
create policy personnel_assignments_update on public.personnel_assignments for update to authenticated
  using (janitra_private.has_site_role(agency_id, site_id, array['supervisor']))
  with check (janitra_private.has_site_role(agency_id, site_id, array['supervisor']));

create policy audit_events_read on public.audit_events for select to authenticated
  using (janitra_private.has_site_role(agency_id, site_id, array['supervisor']));

-- Only table triggers can append this history; credentials are never included.
create function janitra_private.record_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; old_data jsonb;
begin
  row_data := to_jsonb(new);
  if tg_op = 'UPDATE' then old_data := to_jsonb(old); end if;
  if tg_table_name = 'profiles' then
    insert into public.audit_events(actor_id, agency_id, site_id, entity_type, entity_id, action, before_data, after_data)
      select distinct auth.uid(), r.agency_id, r.site_id, tg_table_name,
        (row_data->>'id')::uuid, lower(tg_op), old_data, row_data
      from public.role_assignments r where r.user_id=(row_data->>'id')::uuid;
    return new;
  end if;
  insert into public.audit_events(actor_id, agency_id, site_id, entity_type, entity_id, action, before_data, after_data)
  values (auth.uid(),
    case when tg_table_name = 'agencies' then (row_data->>'id')::uuid else (row_data->>'agency_id')::uuid end,
    case when tg_table_name = 'sites' then (row_data->>'id')::uuid else (row_data->>'site_id')::uuid end,
    tg_table_name, (row_data->>'id')::uuid, lower(tg_op), old_data, row_data);
  return new;
end;
$$;
revoke all on function janitra_private.record_change() from public, anon, authenticated;

create trigger agencies_audit after insert or update on public.agencies for each row execute function janitra_private.record_change();
create trigger clients_audit after insert or update on public.client_companies for each row execute function janitra_private.record_change();
create trigger sites_audit after insert or update on public.sites for each row execute function janitra_private.record_change();
create trigger contracts_audit after insert or update on public.service_contracts for each row execute function janitra_private.record_change();
create trigger roles_audit after insert or update on public.role_assignments for each row execute function janitra_private.record_change();
create trigger personnel_audit after insert or update on public.personnel_assignments for each row execute function janitra_private.record_change();
create trigger profiles_audit after update on public.profiles for each row execute function janitra_private.record_change();

commit;
