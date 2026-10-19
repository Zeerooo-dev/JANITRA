begin;

create table public.work_activities (
 id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.agencies(id),
 site_id uuid not null, name text not null check(length(btrim(name)) between 1 and 200),
 location text not null default '' check(length(location)<=200), instructions text not null default '' check(length(instructions)<=4000),
 is_active boolean not null default true, foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(id,agency_id,site_id)
);
create table public.shift_templates (
 id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 user_id uuid not null references public.profiles(id), name text not null check(length(btrim(name)) between 1 and 200),
 weekdays integer[] not null check(cardinality(weekdays)>0 and weekdays <@ array[1,2,3,4,5,6,7]),
 starts_on date not null, ends_on date, is_active boolean not null default true,
 check(ends_on is null or ends_on>=starts_on), foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(id,agency_id,site_id,user_id)
);
create table public.shift_segments (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.shift_templates(id),
 agency_id uuid not null references public.agencies(id), site_id uuid not null,
 start_minute integer not null check(start_minute between 0 and 2879), end_minute integer not null,
 kind text not null check(kind in ('work','break')), check(end_minute>start_minute and end_minute<=start_minute+1440),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table public.deadline_policies (
 id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 weekday integer not null check(weekday between 1 and 7), hours integer not null check(hours between 1 and 168),
 foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(site_id,weekday)
);
create table public.task_schedule_rules (
 id uuid primary key default gen_random_uuid(), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 user_id uuid not null references public.profiles(id), activity_id uuid not null,
 shift_id uuid, weekdays integer[] not null check(cardinality(weekdays)>0 and weekdays <@ array[1,2,3,4,5,6,7]),
 starts_on date not null, ends_on date, at_minute integer not null check(at_minute between 0 and 1439),
 until_minute integer not null check(until_minute between 0 and 2879), interval_minutes integer check(interval_minutes between 1 and 1440),
 is_active boolean not null default true, check(ends_on is null or ends_on>=starts_on), check(until_minute>=at_minute),
 foreign key(site_id,agency_id) references public.sites(id,agency_id),
 foreign key(activity_id,agency_id,site_id) references public.work_activities(id,agency_id,site_id),
 foreign key(shift_id,agency_id,site_id,user_id) references public.shift_templates(id,agency_id,site_id,user_id)
);
create table public.schedule_exceptions (
 id uuid primary key default gen_random_uuid(), rule_id uuid not null references public.task_schedule_rules(id),
 agency_id uuid not null references public.agencies(id), site_id uuid not null, work_date date not null,
 cancelled boolean not null default false, substitute_id uuid references public.profiles(id), at_minute integer check(at_minute between 0 and 1439),
 reason text not null check(length(btrim(reason)) between 1 and 2000),
 foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(rule_id,work_date)
);
create table public.task_instances (
 id uuid primary key default gen_random_uuid(), rule_id uuid not null references public.task_schedule_rules(id),
 agency_id uuid not null references public.agencies(id), site_id uuid not null,
 user_id uuid not null references public.profiles(id), recurrence_date date not null, slot_minute integer not null,
 work_date date not null, scheduled_at timestamptz not null, original_deadline timestamptz not null, review_deadline timestamptz not null,
 status text not null default 'SCHEDULED' check(status in ('SCHEDULED','PENDING_APPROVAL','APPROVED','REJECTED','LOCKED_NOT_REVIEWED','REOPENED_FOR_REVIEW','CANCELLED')),
 version integer not null default 0, review_cycle integer not null default 0,
 activity_name text not null, location text not null, instructions text not null,
 agency_name text not null, client_name text not null, site_name text not null, personnel_name text not null,
 submitted_at timestamptz, claimed_completed_at timestamptz, remarks text not null default '' check(length(remarks)<=2000),
 verified_at timestamptz, verified_by uuid references public.profiles(id), verifier_name text,
 decided_at timestamptz, decided_by uuid references public.profiles(id), decider_name text, decision_reason text,
 locked_at timestamptz, foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(rule_id,recurrence_date,slot_minute)
);
create table public.task_submissions (
 id uuid primary key default gen_random_uuid(), task_id uuid not null unique references public.task_instances(id),
 agency_id uuid not null references public.agencies(id), site_id uuid not null, user_id uuid not null references public.profiles(id),
 received_at timestamptz not null default clock_timestamp(), claimed_completed_at timestamptz, remarks text not null check(length(remarks)<=2000),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table public.employee_pin_confirmation_events (
 id uuid primary key default gen_random_uuid(), task_id uuid not null unique references public.task_instances(id),
 submission_id uuid not null unique references public.task_submissions(id), actor_id uuid not null references public.profiles(id),
 agency_id uuid not null references public.agencies(id), site_id uuid not null, occurred_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table public.supervisor_confirmations (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.task_instances(id), review_cycle integer not null,
 actor_id uuid not null references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 occurred_at timestamptz not null default clock_timestamp(), foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(task_id,review_cycle)
);
create table public.approval_events (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.task_instances(id), review_cycle integer not null,
 actor_id uuid not null references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 outcome text not null check(outcome in ('APPROVED','REJECTED')), reason text not null default '', occurred_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(task_id,review_cycle), check(outcome<>'REJECTED' or length(btrim(reason))>0)
);
create table public.lock_overrides (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.task_instances(id), review_cycle integer not null,
 actor_id uuid not null references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 original_deadline timestamptz not null, new_deadline timestamptz not null, reason text not null check(length(btrim(reason)) between 10 and 2000),
 occurred_at timestamptz not null default clock_timestamp(), foreign key(site_id,agency_id) references public.sites(id,agency_id), unique(task_id,review_cycle)
);
create table public.task_events (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.task_instances(id),
 actor_id uuid references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 event text not null, details jsonb not null default '{}', occurred_at timestamptz not null default clock_timestamp(),
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table public.task_notifications (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.task_instances(id),
 recipient_id uuid not null references public.profiles(id), agency_id uuid not null references public.agencies(id), site_id uuid not null,
 message text not null, occurred_at timestamptz not null default clock_timestamp(), read_at timestamptz,
 foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table public.report_exports (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 agency_id uuid not null references public.agencies(id), site_id uuid, from_date date not null,to_date date not null,
 format text not null check(format in ('pdf','xlsx')), filters jsonb not null, row_count integer not null, source_hash text not null,
 occurred_at timestamptz not null default clock_timestamp(), foreign key(site_id,agency_id) references public.sites(id,agency_id)
);
create table janitra_private.workflow_requests (
 actor_id uuid not null references public.profiles(id), request_id uuid not null, action text not null,
 binding text not null, result jsonb not null, occurred_at timestamptz not null default clock_timestamp(), primary key(actor_id,request_id)
);
alter table janitra_private.workflow_requests enable row level security;
revoke all on janitra_private.workflow_requests from public,anon,authenticated,service_role;
create table janitra_private.generation_days(work_date date primary key);
alter table janitra_private.generation_days enable row level security;
revoke all on janitra_private.generation_days from public,anon,authenticated,service_role;

create index activities_scope_idx on public.work_activities(agency_id,site_id);
create index shifts_user_idx on public.shift_templates(user_id,site_id);
create index shifts_scope_idx on public.shift_templates(agency_id,site_id);
create index segments_template_idx on public.shift_segments(template_id);
create index rules_scope_idx on public.task_schedule_rules(agency_id,site_id,user_id);
create index rules_activity_idx on public.task_schedule_rules(activity_id);
create index rules_shift_idx on public.task_schedule_rules(shift_id);
create index exceptions_date_idx on public.schedule_exceptions(agency_id,site_id,work_date);
create index tasks_scope_date_idx on public.task_instances(agency_id,site_id,work_date,id);
create index tasks_user_date_idx on public.task_instances(user_id,scheduled_at,id);
create index tasks_deadline_idx on public.task_instances(review_deadline) where status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW');
create index notifications_user_idx on public.task_notifications(recipient_id,occurred_at desc);
create index events_task_idx on public.task_events(task_id,occurred_at,id);
create index reports_scope_idx on public.report_exports(agency_id,site_id,occurred_at);

create function janitra_private.live_auth_session() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s where s.user_id=auth.uid() and s.id=
  case when (auth.jwt()->>'session_id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   then (auth.jwt()->>'session_id')::uuid else null end and (s.not_after is null or s.not_after>clock_timestamp()));
$$;
revoke all on function janitra_private.live_auth_session() from public,anon,service_role;
grant execute on function janitra_private.live_auth_session() to authenticated;
create function public.actor_session_valid(p_actor uuid,p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s join public.profiles p on p.id=s.user_id where s.id=p_session and s.user_id=p_actor and p.is_active and (s.not_after is null or s.not_after>clock_timestamp())
  and exists(select 1 from public.role_assignments r where r.user_id=p_actor and r.is_active));
$$;
revoke all on function public.actor_session_valid(uuid,uuid) from public,anon,authenticated;
grant execute on function public.actor_session_valid(uuid,uuid) to service_role;
create function public.actor_session_state(p_actor uuid,p_session uuid) returns text language sql stable security definer set search_path='' as $$
 select case when not exists(select 1 from public.profiles where id=p_actor and is_active) then 'suspended'
  when not exists(select 1 from public.role_assignments where user_id=p_actor and is_active) then 'revoked'
  when not exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp())) then 'expired' else 'active' end;
$$;
revoke all on function public.actor_session_state(uuid,uuid) from public,anon,authenticated;
grant execute on function public.actor_session_state(uuid,uuid) to service_role;
alter policy profiles_read on public.profiles using(janitra_private.live_auth_session() and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false
 and ((id=auth.uid() and is_active) or exists(select 1 from public.role_assignments r where r.user_id=profiles.id and janitra_private.has_site_role(r.agency_id,r.site_id,array['supervisor']))));
alter policy profiles_update_name on public.profiles using(id=auth.uid() and is_active and janitra_private.live_auth_session() and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false)
 with check(id=auth.uid() and is_active and janitra_private.live_auth_session() and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false);
alter policy transfer_history on public.agency_transfers using(janitra_private.live_auth_session() and (
 janitra_private.has_site_role(agency_id,null,array['supervisor']) or janitra_private.has_site_role(destination_agency_id,site_id,array['supervisor'])
 or (user_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and is_active))));
create or replace function janitra_private.has_site_role(target_agency uuid,target_site uuid,required_roles text[])
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false
  and exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
   where r.user_id=auth.uid() and p.is_active and r.is_active and r.agency_id=target_agency and r.role=any(required_roles) and (r.site_id is null or r.site_id=target_site));
$$;
create or replace function janitra_private.is_agency_member(target_agency uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select janitra_private.live_auth_session() and auth.uid() is not null and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false
  and exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id
   where r.user_id=auth.uid() and p.is_active and r.is_active and r.agency_id=target_agency);
$$;
create view public.task_work_view with(security_invoker=true) as select ti.*,statement_timestamp() as checked_at,
 case when ti.status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') and ti.review_deadline<=statement_timestamp() then 'LOCKED_NOT_REVIEWED'
  when ti.status='SCHEDULED' and ti.review_deadline<=statement_timestamp() then 'NOT_SUBMITTED' else ti.status end as effective_status
 from public.task_instances ti;
revoke all on public.task_work_view from public,anon,service_role;
grant select on public.task_work_view to authenticated;

create function janitra_private.can_read_work(p_user uuid,p_agency uuid,p_site uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select janitra_private.has_site_role(p_agency,p_site,array['supervisor']) or
  (p_user=auth.uid() and janitra_private.live_auth_session() and exists(select 1 from public.profiles p join public.role_assignments r on r.user_id=p.id
   where p.id=auth.uid() and p.is_active and r.is_active and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false));
$$;
revoke all on function janitra_private.can_read_work(uuid,uuid,uuid) from public,anon,service_role;
grant execute on function janitra_private.can_read_work(uuid,uuid,uuid) to authenticated;

do $$ declare tab text; begin
 foreach tab in array array['work_activities','shift_templates','shift_segments','deadline_policies','task_schedule_rules','schedule_exceptions',
  'task_instances','task_submissions','employee_pin_confirmation_events','supervisor_confirmations','approval_events','lock_overrides','task_events','task_notifications','report_exports'] loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',tab);
  execute format('grant select on public.%I to authenticated',tab);
  if tab in ('task_instances','task_submissions','shift_templates','task_schedule_rules') then
   execute format('create policy work_read on public.%I for select to authenticated using(janitra_private.can_read_work(user_id,agency_id,site_id))',tab);
  elsif tab in ('employee_pin_confirmation_events','supervisor_confirmations','approval_events','lock_overrides','task_events') then
   execute format('create policy work_read on public.%I for select to authenticated using(exists(select 1 from public.task_instances t where t.id=task_id))',tab);
  elsif tab='task_notifications' then
   execute format('create policy work_read on public.%I for select to authenticated using(recipient_id=auth.uid() and exists(select 1 from public.task_instances t where t.id=task_id))',tab);
  elsif tab='shift_segments' then
   execute format('create policy work_read on public.%I for select to authenticated using(exists(select 1 from public.shift_templates s where s.id=template_id))',tab);
  elsif tab='schedule_exceptions' then
   execute format('create policy work_read on public.%I for select to authenticated using(exists(select 1 from public.task_schedule_rules r where r.id=rule_id))',tab);
  elsif tab='report_exports' then
   execute format('create policy work_read on public.%I for select to authenticated using(janitra_private.has_site_role(agency_id,site_id,array[''supervisor'']))',tab);
  else
   execute format('create policy work_read on public.%I for select to authenticated using(janitra_private.has_site_role(agency_id,site_id,array[''supervisor'',''personnel'']))',tab);
  end if;
  if tab in ('work_activities','shift_templates','deadline_policies','task_schedule_rules','schedule_exceptions','task_instances','report_exports') then
   execute format('create trigger work_audit after insert or update on public.%I for each row execute function janitra_private.record_change()',tab);
  end if;
 end loop;
end $$;

create function janitra_private.work_deadline(p_scheduled timestamptz,p_site uuid) returns timestamptz
language sql stable security definer set search_path='' as $$
 select case when extract(isodow from p_scheduled at time zone 'Asia/Manila')=6
  then (((p_scheduled at time zone 'Asia/Manila')::date+2)+time '12:00') at time zone 'Asia/Manila'
  else p_scheduled + make_interval(hours=>coalesce((select hours from public.deadline_policies
    where site_id=p_site and weekday=extract(isodow from p_scheduled at time zone 'Asia/Manila')),24)) end;
$$;
revoke all on function janitra_private.work_deadline(timestamptz,uuid) from public,anon,authenticated,service_role;

create function janitra_private.emit_work_event(p_task uuid,p_actor uuid,p_event text,p_details jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare t public.task_instances%rowtype;
begin
 select * into strict t from public.task_instances where id=p_task;
 insert into public.task_events(task_id,actor_id,agency_id,site_id,event,details) values(t.id,p_actor,t.agency_id,t.site_id,p_event,p_details);
 if p_event='submitted' then
  insert into public.task_notifications(task_id,recipient_id,agency_id,site_id,message)
   select distinct t.id,r.user_id,t.agency_id,t.site_id,t.personnel_name||' submitted '||t.activity_name||'.'
   from public.role_assignments r join public.profiles p on p.id=r.user_id
   where p.is_active and r.is_active and r.role='supervisor' and r.agency_id=t.agency_id and (r.site_id is null or r.site_id=t.site_id);
 elsif p_event<>'scheduled' then
  insert into public.task_notifications(task_id,recipient_id,agency_id,site_id,message)
   values(t.id,t.user_id,t.agency_id,t.site_id,t.activity_name||': '||replace(p_event,'_',' ')||'.');
 end if;
end; $$;
revoke all on function janitra_private.emit_work_event(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;

create function janitra_private.generate_work(p_from date,p_until date,p_agency uuid default null) returns integer
language plpgsql security definer set search_path='' as $$
declare r record; day date; slot integer; planned timestamptz; target uuid; inserted uuid; ex public.schedule_exceptions%rowtype; generated integer:=0;
begin
 if p_until-p_from>31 or p_until<p_from then raise exception 'Generation range too large'; end if;
 for r in select sr.*,a.name as activity_name,a.location,a.instructions,ag.name as agency_name,s.name as site_name,c.name as client_name
  from public.task_schedule_rules sr join public.work_activities a on a.id=sr.activity_id
  join public.agencies ag on ag.id=sr.agency_id join public.sites s on s.id=sr.site_id join public.client_companies c on c.id=s.client_company_id
  where sr.is_active and a.is_active and (p_agency is null or sr.agency_id=p_agency) loop
  for day in select d::date from generate_series(p_from::timestamp,p_until::timestamp,interval '1 day') d loop
   if day<r.starts_on or (r.ends_on is not null and day>r.ends_on) or not (extract(isodow from day)::integer=any(r.weekdays)) then continue; end if;
   select * into ex from public.schedule_exceptions where rule_id=r.id and work_date=day;
   if ex.cancelled then continue; end if;
   target:=coalesce(ex.substitute_id,r.user_id);
   if not exists(select 1 from public.role_assignments ra join public.profiles p on p.id=ra.user_id
    where ra.user_id=target and p.is_active and ra.is_active and ra.role='personnel' and ra.agency_id=r.agency_id and ra.site_id=r.site_id) then continue; end if;
   for slot in select m from generate_series(coalesce(ex.at_minute,r.at_minute),
    case when ex.at_minute is not null or r.interval_minutes is null then coalesce(ex.at_minute,r.at_minute) else r.until_minute end,coalesce(r.interval_minutes,1)) m loop
    if r.shift_id is not null and not exists(select 1 from public.shift_templates st where st.id=r.shift_id and st.is_active
      and day>=st.starts_on and (st.ends_on is null or day<=st.ends_on) and extract(isodow from day)::integer=any(st.weekdays)
      and exists(select 1 from public.shift_segments where template_id=st.id and kind='work' and slot>=start_minute and slot<end_minute)
      and not exists(select 1 from public.shift_segments where template_id=st.id and kind='break' and slot>=start_minute and slot<end_minute)) then continue; end if;
    planned:=(day::timestamp+make_interval(mins=>slot)) at time zone 'Asia/Manila';
    if exists(select 1 from public.task_instances where rule_id=r.id and recurrence_date=day and slot_minute=slot
      and (status<>'CANCELLED' or scheduled_at<=clock_timestamp() or planned<=clock_timestamp())) then continue; end if;
    inserted:=null;
    insert into public.task_instances(rule_id,agency_id,site_id,user_id,recurrence_date,slot_minute,work_date,scheduled_at,original_deadline,review_deadline,
      activity_name,location,instructions,agency_name,client_name,site_name,personnel_name)
     values(r.id,r.agency_id,r.site_id,target,day,slot,(planned at time zone 'Asia/Manila')::date,planned,
      janitra_private.work_deadline(planned,r.site_id),janitra_private.work_deadline(planned,r.site_id),r.activity_name,r.location,r.instructions,
      r.agency_name,r.client_name,r.site_name,(select full_name from public.profiles where id=target))
     on conflict(rule_id,recurrence_date,slot_minute) do update set status='SCHEDULED',user_id=excluded.user_id,scheduled_at=excluded.scheduled_at,
      original_deadline=excluded.original_deadline,review_deadline=excluded.review_deadline,activity_name=excluded.activity_name,location=excluded.location,
      instructions=excluded.instructions,personnel_name=excluded.personnel_name,version=task_instances.version+1
     where task_instances.status='CANCELLED' and task_instances.scheduled_at>clock_timestamp() and excluded.scheduled_at>clock_timestamp()
     returning id into inserted;
    if inserted is not null then generated:=generated+1; perform janitra_private.emit_work_event(inserted,null,'scheduled'); end if;
   end loop;
  end loop;
 end loop;
 return generated;
end; $$;
revoke all on function janitra_private.generate_work(date,date,uuid) from public,anon,authenticated,service_role;

create function janitra_private.lock_work(p_task uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare changed uuid;
begin
 update public.task_instances set status='LOCKED_NOT_REVIEWED',locked_at=review_deadline,version=version+1
  where id=p_task and status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') and review_deadline<=clock_timestamp() returning id into changed;
 if changed is not null then perform janitra_private.emit_work_event(changed,null,'locked'); return true; end if;
 return false;
end; $$;
revoke all on function janitra_private.lock_work(uuid) from public,anon,authenticated,service_role;
create function janitra_private.workflow_tick() returns void language plpgsql security definer set search_path='' as $$
declare t record; generated_day date; today date:=(clock_timestamp() at time zone 'Asia/Manila')::date;
begin
 insert into janitra_private.generation_days values(today) on conflict do nothing returning work_date into generated_day;
 if generated_day is not null then perform janitra_private.generate_work(today-1,today+14);end if;
 delete from janitra_private.generation_days where work_date<today-31;
 for t in select id from public.task_instances where status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') and review_deadline<=clock_timestamp()
  order by id for update skip locked loop perform janitra_private.lock_work(t.id); end loop;
end; $$;
revoke all on function janitra_private.workflow_tick() from public,anon,authenticated,service_role;

create function janitra_private.after_agency_transfer() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.task_schedule_rules set is_active=false where user_id=new.user_id and agency_id=new.agency_id and is_active;
 update public.shift_templates set is_active=false where user_id=new.user_id and agency_id=new.agency_id and is_active;
 update public.task_instances set status='CANCELLED',version=version+1 where user_id=new.user_id and agency_id=new.agency_id
  and status='SCHEDULED' and scheduled_at>clock_timestamp();
 return new;
end; $$;
revoke all on function janitra_private.after_agency_transfer() from public,anon,authenticated,service_role;
create trigger transfer_future_work after insert on public.agency_transfers for each row execute function janitra_private.after_agency_transfer();

create function public.workflow_command(p_actor uuid,p_session uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.task_instances%rowtype; agency uuid; site uuid; employee uuid; item uuid; req uuid; binding text;
 result jsonb; receipt janitra_private.workflow_requests%rowtype; now_at timestamptz; outcome text; submission uuid;
 weekdays integer[]; segment jsonb; rows jsonb; count_rows integer; from_day date; to_day date; today date:=(clock_timestamp() at time zone 'Asia/Manila')::date;
begin
 perform 1 from auth.sessions where id=p_session and user_id=p_actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'Session expired' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_actor and is_active for share;
 if not found then raise exception 'Account suspended' using errcode='42501'; end if;
 if not exists(select 1 from public.role_assignments where user_id=p_actor and is_active) then raise exception 'Account access revoked' using errcode='42501'; end if;
 req:=(p_data->>'request_id')::uuid;
 if req is null then raise exception 'Request identifier required'; end if;
 binding:=encode(extensions.digest((p_data-'digest'-'password'-'pin')::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||req::text,0));
 select * into receipt from janitra_private.workflow_requests where actor_id=p_actor and request_id=req;
 if found then
  if receipt.action<>p_action or receipt.binding<>binding then raise exception 'Request conflict' using errcode='23505'; end if;
  if p_action in ('submit','verify','approve','reject','override') then
   select * into t from public.task_instances where id=(p_data->>'task_id')::uuid;
   if not found or (p_action='submit' and (t.user_id<>p_actor or not exists(select 1 from public.role_assignments where user_id=p_actor and agency_id=t.agency_id and site_id=t.site_id and role='personnel' and is_active))) or (p_action<>'submit' and not janitra_private.manager_has_scope(p_actor,t.agency_id,t.site_id))
    then raise exception 'Receipt access revoked' using errcode='42501'; end if;
  elsif p_action<>'read_notifications' and not janitra_private.manager_has_scope(p_actor,(p_data->>'agency_id')::uuid,(p_data->>'site_id')::uuid)
   then raise exception 'Receipt access revoked' using errcode='42501';
  end if;
  return receipt.result;
 end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor,'role','authenticated','is_anonymous',false)::text,true);
 if p_action in ('submit','verify','approve','reject','override') then
  select * into t from public.task_instances where id=(p_data->>'task_id')::uuid;
  if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
  if p_action='submit' then
   if t.user_id<>p_actor then raise exception 'Task belongs to another person' using errcode='42501'; end if;
   perform 1 from public.role_assignments where user_id=p_actor and agency_id=t.agency_id and site_id=t.site_id and is_active and role='personnel' for share;
  else
   perform 1 from public.role_assignments where user_id=p_actor and agency_id=t.agency_id and (site_id is null or site_id=t.site_id) and is_active and role='supervisor' for share;
  end if;
  if not found then raise exception 'Task access revoked' using errcode='42501'; end if;
  select * into strict t from public.task_instances where id=t.id for update;
  if janitra_private.lock_work(t.id) then select * into strict t from public.task_instances where id=t.id; end if;
  if t.version<>coalesce((p_data->>'version')::integer,-1) then
   return jsonb_build_object('ok',false,'code','conflict','message','This task changed. Refresh it before continuing.');
  end if;
  if p_action='override' then
   now_at:=clock_timestamp();
   if coalesce((p_data->>'_reauth')::boolean,false)=false or t.status<>'LOCKED_NOT_REVIEWED' or length(btrim(coalesce(p_data->>'reason','')))<10
    or (p_data->>'deadline')::timestamptz<=now_at or (p_data->>'deadline')::timestamptz>now_at+interval '7 days'
    or p_data->>'deadline' is null then raise exception 'Provide a justification and a future deadline within seven days'; end if;
   update public.task_instances set status='REOPENED_FOR_REVIEW',review_cycle=review_cycle+1,review_deadline=(p_data->>'deadline')::timestamptz,
    verified_at=null,verified_by=null,verifier_name=null,version=version+1 where id=t.id;
   insert into public.lock_overrides(task_id,review_cycle,actor_id,agency_id,site_id,original_deadline,new_deadline,reason)
    values(t.id,t.review_cycle+1,p_actor,t.agency_id,t.site_id,t.original_deadline,(p_data->>'deadline')::timestamptz,btrim(p_data->>'reason'));
   perform janitra_private.emit_work_event(t.id,p_actor,'reopened',jsonb_build_object('reason',btrim(p_data->>'reason'),'original_deadline',t.original_deadline,'deadline',p_data->>'deadline'));
  else
   if t.review_deadline<=clock_timestamp() or t.status='LOCKED_NOT_REVIEWED' then
    return jsonb_build_object('ok',false,'code','deadline','message','The review deadline has passed. An authorized Supervisor must reopen submitted work.');
   end if;
   if p_action='submit' and (t.status<>'SCHEDULED' or t.scheduled_at>clock_timestamp()) then
    return jsonb_build_object('ok',false,'code','state','message','This task is already submitted, cancelled, or not due yet.');
   elsif p_action<>'submit' and t.status not in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') then
    return jsonb_build_object('ok',false,'code','state','message','This task is not awaiting review.');
   end if;
   if p_action in ('submit','verify') then
    if p_action='verify' and t.verified_at is not null then return jsonb_build_object('ok',false,'code','state','message','Work is already verified.'); end if;
    if length(coalesce(p_data->>'remarks',''))>2000 or (p_data->>'claimed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then raise exception 'Invalid completion details'; end if;
    outcome:=janitra_private.verify_pin(p_actor,case when p_action='submit' then 'employee' else 'supervisor' end,t.agency_id,t.site_id,p_data->>'digest');
    if outcome<>'verified' then
     result:=jsonb_build_object('ok',false,'code',outcome,'message',case outcome when 'locked' then 'PIN attempts are locked. Try again after 15 minutes.' when 'incorrect' then 'Incorrect PIN.' when 'not_configured' then 'Your PIN has not been configured.' else 'PIN confirmation is not authorized.' end);
     insert into janitra_private.workflow_requests values(p_actor,req,p_action,binding,result,clock_timestamp());
     return result;
    end if;
    now_at:=clock_timestamp();
    if now_at>=t.review_deadline then
     perform janitra_private.lock_work(t.id);
     return jsonb_build_object('ok',false,'code','deadline','message','The review deadline passed during confirmation. Refresh this task.');
    end if;
    if p_action='submit' then
     insert into public.task_submissions(task_id,agency_id,site_id,user_id,received_at,claimed_completed_at,remarks)
      values(t.id,t.agency_id,t.site_id,p_actor,now_at,(p_data->>'claimed_at')::timestamptz,coalesce(p_data->>'remarks','')) returning id into submission;
     insert into public.employee_pin_confirmation_events(task_id,submission_id,actor_id,agency_id,site_id,occurred_at)
      values(t.id,submission,p_actor,t.agency_id,t.site_id,now_at);
     update public.task_instances set status='PENDING_APPROVAL',submitted_at=now_at,claimed_completed_at=(p_data->>'claimed_at')::timestamptz,
      remarks=coalesce(p_data->>'remarks',''),version=version+1 where id=t.id;
     perform janitra_private.emit_work_event(t.id,p_actor,'submitted');
    else
     insert into public.supervisor_confirmations(task_id,review_cycle,actor_id,agency_id,site_id,occurred_at) values(t.id,t.review_cycle,p_actor,t.agency_id,t.site_id,now_at);
     update public.task_instances set verified_at=now_at,verified_by=p_actor,verifier_name=(select full_name from public.profiles where id=p_actor),version=version+1 where id=t.id;
     perform janitra_private.emit_work_event(t.id,p_actor,'supervisor_verified');
    end if;
   else
    if t.verified_at is null then return jsonb_build_object('ok',false,'code','unverified','message','Confirm work with your Supervisor PIN before the final decision.'); end if;
    if p_action='reject' and length(btrim(coalesce(p_data->>'reason','')))=0 then raise exception 'Rejection needs a reason'; end if;
    now_at:=clock_timestamp();
    if now_at>=t.review_deadline then perform janitra_private.lock_work(t.id); return jsonb_build_object('ok',false,'code','deadline','message','Review deadline passed.'); end if;
    outcome:=case when p_action='approve' then 'APPROVED' else 'REJECTED' end;
    insert into public.approval_events(task_id,review_cycle,actor_id,agency_id,site_id,outcome,reason,occurred_at)
     values(t.id,t.review_cycle,p_actor,t.agency_id,t.site_id,outcome,coalesce(btrim(p_data->>'reason'),''),now_at);
    update public.task_instances set status=outcome,decided_at=now_at,decided_by=p_actor,decider_name=(select full_name from public.profiles where id=p_actor),
     decision_reason=coalesce(btrim(p_data->>'reason'),''),version=version+1 where id=t.id;
    perform janitra_private.emit_work_event(t.id,p_actor,lower(outcome),jsonb_build_object('reason',coalesce(btrim(p_data->>'reason'),'')));
   end if;
  end if;
  select jsonb_build_object('ok',true,'task',to_jsonb(ti)) into result from public.task_instances ti where id=t.id;
 else
  agency:=(p_data->>'agency_id')::uuid; site:=(p_data->>'site_id')::uuid;
  if p_action='read_notifications' then
   update public.task_notifications set read_at=clock_timestamp() where recipient_id=p_actor and read_at is null;
   result:=jsonb_build_object('ok',true);
  else
   perform 1 from public.role_assignments where user_id=p_actor and role='supervisor' and is_active and agency_id=agency and (site_id is null or site_id=site) for share;
   if not found then raise exception 'Supervisor scope required' using errcode='42501'; end if;
   if p_action='report' then
    now_at:=clock_timestamp();
    from_day:=(p_data->>'from_date')::date; to_day:=(p_data->>'to_date')::date;
    if from_day is null or to_day is null or to_day<from_day or to_day-from_day>366 or p_data->>'format' not in ('pdf','xlsx') then raise exception 'Choose a reporting period within one year'; end if;
    select count(*),jsonb_agg(to_jsonb(q) order by q.work_date,q.scheduled_at,q.id) into count_rows,rows from (
      select ti.*,case when ti.status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') and ti.review_deadline<=now_at then 'LOCKED_NOT_REVIEWED'
       when ti.status='SCHEDULED' and ti.review_deadline<=now_at then 'NOT_SUBMITTED' else ti.status end as report_status,
       coalesce((select jsonb_agg(to_jsonb(o)) from public.lock_overrides o where o.task_id=ti.id),'[]'::jsonb) as overrides
      from public.task_instances ti where ti.agency_id=agency and (site is null or ti.site_id=site) and ti.work_date between from_day and to_day
       and janitra_private.manager_has_scope(p_actor,ti.agency_id,ti.site_id)
       and (p_data->>'user_id' is null or ti.user_id=(p_data->>'user_id')::uuid)
       and (p_data->>'supervisor_id' is null or ti.verified_by=(p_data->>'supervisor_id')::uuid or ti.decided_by=(p_data->>'supervisor_id')::uuid)
       and (p_data->>'status' is null or (case when ti.status in ('PENDING_APPROVAL','REOPENED_FOR_REVIEW') and ti.review_deadline<=now_at then 'LOCKED_NOT_REVIEWED'
        when ti.status='SCHEDULED' and ti.review_deadline<=now_at then 'NOT_SUBMITTED' else ti.status end)=p_data->>'status') order by ti.work_date,ti.id limit 10001
    ) q;
    if count_rows>10000 then raise exception 'Too many records. Choose a shorter period or narrower filter.'; end if;
    if octet_length(coalesce(rows,'[]'::jsonb)::text)>4000000 then raise exception 'Report is too large. Choose a shorter period or narrower filter.'; end if;
    insert into public.report_exports(actor_id,agency_id,site_id,from_date,to_date,format,filters,row_count,source_hash)
      values(p_actor,agency,site,from_day,to_day,p_data->>'format',p_data-'request_id',count_rows,md5(coalesce(rows,'[]'::jsonb)::text)) returning id into item;
    result:=jsonb_build_object('ok',true,'report_id',item,'records',coalesce(rows,'[]'::jsonb),'generated_at',now_at);
   else
    if site is null or not exists(select 1 from public.sites where id=site and agency_id=agency) then raise exception 'Choose an authorized workplace'; end if;
    item:=coalesce((p_data->>'id')::uuid,gen_random_uuid()); employee:=(p_data->>'user_id')::uuid;
    if p_action='activity_save' and exists(select 1 from public.work_activities where id=item and (agency_id<>agency or site_id<>site))
      or p_action='shift_save' and exists(select 1 from public.shift_templates where id=item and (agency_id<>agency or site_id<>site or user_id<>employee))
      or p_action='rule_save' and exists(select 1 from public.task_schedule_rules where id=item and (agency_id<>agency or site_id<>site or user_id<>employee))
    then raise exception 'Record is outside your scope' using errcode='42501'; end if;
    if p_action in ('shift_save','rule_save') then
     if not exists(select 1 from public.role_assignments r join public.profiles p on p.id=r.user_id where r.user_id=employee and r.agency_id=agency and r.site_id=site and r.role='personnel' and r.is_active and p.is_active) then raise exception 'Choose active assigned Personnel'; end if;
     select array_agg(value::integer) into weekdays from jsonb_array_elements_text(p_data->'weekdays');
     if weekdays is null or cardinality(weekdays)=0 then raise exception 'Choose working days'; end if;
    end if;
    if p_action='activity_save' then
     insert into public.work_activities(id,agency_id,site_id,name,location,instructions,is_active)
      values(item,agency,site,btrim(p_data->>'name'),coalesce(p_data->>'location',''),coalesce(p_data->>'instructions',''),coalesce((p_data->>'is_active')::boolean,true))
      on conflict(id) do update set name=excluded.name,location=excluded.location,instructions=excluded.instructions,is_active=excluded.is_active
       where work_activities.agency_id=agency and work_activities.site_id=site;
     update public.task_instances set status='CANCELLED',version=version+1 where rule_id in(select id from public.task_schedule_rules where activity_id=item) and status='SCHEDULED' and scheduled_at>clock_timestamp();
    elsif p_action='shift_save' then
     if jsonb_typeof(p_data->'segments')<>'array' or jsonb_array_length(p_data->'segments') not between 1 and 12 then raise exception 'Provide one to twelve shift/break segments'; end if;
     if exists(select 1 from jsonb_array_elements(p_data->'segments') a join jsonb_array_elements(p_data->'segments') b on a<>b
       where a->>'kind'='work' and b->>'kind'='work' and (a->>'start')::integer<(b->>'end')::integer and (b->>'start')::integer<(a->>'end')::integer)
       or exists(select 1 from jsonb_array_elements(p_data->'segments') b where b->>'kind'='break' and not exists(
        select 1 from jsonb_array_elements(p_data->'segments') w where w->>'kind'='work' and (b->>'start')::integer>=(w->>'start')::integer and (b->>'end')::integer<=(w->>'end')::integer))
       then raise exception 'Work shifts must not overlap; breaks must fit inside a work shift'; end if;
     insert into public.shift_templates(id,agency_id,site_id,user_id,name,weekdays,starts_on,ends_on,is_active)
      values(item,agency,site,employee,btrim(p_data->>'name'),weekdays,(p_data->>'starts_on')::date,(p_data->>'ends_on')::date,coalesce((p_data->>'is_active')::boolean,true))
      on conflict(id) do update set name=excluded.name,weekdays=excluded.weekdays,starts_on=excluded.starts_on,ends_on=excluded.ends_on,is_active=excluded.is_active
       where shift_templates.agency_id=agency and shift_templates.site_id=site and shift_templates.user_id=employee;
     delete from public.shift_segments where template_id=item;
     for segment in select value from jsonb_array_elements(p_data->'segments') loop
      insert into public.shift_segments(template_id,agency_id,site_id,start_minute,end_minute,kind) values(item,agency,site,(segment->>'start')::integer,(segment->>'end')::integer,segment->>'kind');
     end loop;
     update public.task_instances set status='CANCELLED',version=version+1 where rule_id in(select id from public.task_schedule_rules where shift_id=item) and status='SCHEDULED' and scheduled_at>clock_timestamp();
    elsif p_action='rule_save' then
     insert into public.task_schedule_rules(id,agency_id,site_id,user_id,activity_id,shift_id,weekdays,starts_on,ends_on,at_minute,until_minute,interval_minutes,is_active)
      values(item,agency,site,employee,(p_data->>'activity_id')::uuid,(p_data->>'shift_id')::uuid,weekdays,(p_data->>'starts_on')::date,(p_data->>'ends_on')::date,
        (p_data->>'at_minute')::integer,coalesce((p_data->>'until_minute')::integer,(p_data->>'at_minute')::integer),(p_data->>'interval_minutes')::integer,coalesce((p_data->>'is_active')::boolean,true))
      on conflict(id) do update set activity_id=excluded.activity_id,shift_id=excluded.shift_id,weekdays=excluded.weekdays,starts_on=excluded.starts_on,ends_on=excluded.ends_on,
       at_minute=excluded.at_minute,until_minute=excluded.until_minute,interval_minutes=excluded.interval_minutes,is_active=excluded.is_active
       where task_schedule_rules.agency_id=agency and task_schedule_rules.site_id=site and task_schedule_rules.user_id=employee;
     update public.task_instances set status='CANCELLED',version=version+1 where rule_id=item and status='SCHEDULED' and scheduled_at>clock_timestamp();
    elsif p_action='exception_save' then
     if not exists(select 1 from public.task_schedule_rules where id=(p_data->>'rule_id')::uuid and agency_id=agency and site_id=site)
      or ((p_data->>'substitute_id')::uuid is not null and not exists(select 1 from public.role_assignments where user_id=(p_data->>'substitute_id')::uuid and agency_id=agency and site_id=site and role='personnel' and is_active)) then raise exception 'Invalid schedule or substitute'; end if;
     if (p_data->>'work_date')::date<today then raise exception 'Past schedule exceptions cannot be edited'; end if;
     insert into public.schedule_exceptions(rule_id,agency_id,site_id,work_date,cancelled,substitute_id,at_minute,reason)
      values((p_data->>'rule_id')::uuid,agency,site,(p_data->>'work_date')::date,coalesce((p_data->>'cancelled')::boolean,false),(p_data->>'substitute_id')::uuid,(p_data->>'at_minute')::integer,btrim(p_data->>'reason'))
      on conflict(rule_id,work_date) do update set cancelled=excluded.cancelled,substitute_id=excluded.substitute_id,at_minute=excluded.at_minute,reason=excluded.reason;
     update public.task_instances set status='CANCELLED',version=version+1 where rule_id=(p_data->>'rule_id')::uuid and recurrence_date=(p_data->>'work_date')::date and status='SCHEDULED' and scheduled_at>clock_timestamp();
    elsif p_action='policy_save' then
     insert into public.deadline_policies(agency_id,site_id,weekday,hours) values(agency,site,(p_data->>'weekday')::integer,(p_data->>'hours')::integer)
      on conflict(site_id,weekday) do update set hours=excluded.hours;
     update public.task_instances set status='CANCELLED',version=version+1 where site_id=site and status='SCHEDULED' and scheduled_at>clock_timestamp();
    else raise exception 'Unknown workflow action'; end if;
    perform janitra_private.generate_work(today-1,today+14,agency);
    result:=jsonb_build_object('ok',true,'id',item);
   end if;
  end if;
 end if;
 insert into janitra_private.workflow_requests values(p_actor,req,p_action,binding,result,clock_timestamp());
 return result;
end; $$;
revoke all on function public.workflow_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.workflow_command(uuid,uuid,text,jsonb) to service_role;

create function janitra_private.record_work_cancellation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='CANCELLED' and old.status<>'CANCELLED' then
  perform janitra_private.emit_work_event(new.id,auth.uid(),'cancelled');
 end if;
 return new;
end; $$;
revoke all on function janitra_private.record_work_cancellation() from public,anon,authenticated,service_role;
create trigger work_cancelled after update on public.task_instances for each row execute function janitra_private.record_work_cancellation();

create function janitra_private.after_personnel_access() returns trigger language plpgsql security definer set search_path='' as $$
declare today date:=(clock_timestamp() at time zone 'Asia/Manila')::date;
begin
 if new.role='personnel' and (tg_op='INSERT' or new.is_active is distinct from old.is_active) then
  if not new.is_active then
   update public.task_instances set status='CANCELLED',version=version+1 where user_id=new.user_id and agency_id=new.agency_id and site_id=new.site_id
    and status='SCHEDULED' and scheduled_at>clock_timestamp();
  else perform janitra_private.generate_work(today-1,today+14,new.agency_id); end if;
 end if;
 return new;
end; $$;
revoke all on function janitra_private.after_personnel_access() from public,anon,authenticated,service_role;
create trigger personnel_work_access after insert or update on public.role_assignments for each row execute function janitra_private.after_personnel_access();

-- Hosted Supabase has pg_cron; isolated vanilla PostgreSQL tests exercise the same tick directly.
do $$ begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('janitra-workflow-minute','* * * * *','select janitra_private.workflow_tick()');
 else raise notice 'pg_cron unavailable: run the tick in isolated tests; hosted deployment must verify its job'; end if;
end $$;
commit;
