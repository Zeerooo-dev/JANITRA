#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
container_name="janitra-rls-test-$$"
concurrency_log=""
trap 'docker rm -f -v "$container_name" >/dev/null 2>&1 || true; if [[ -n "$concurrency_log" ]]; then rm -f "$concurrency_log"; fi' EXIT
docker run --detach --name "$container_name" --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine >/dev/null
for attempt in {1..30}; do
  if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  if [[ "$attempt" == 30 ]]; then echo 'Test database did not start' >&2; exit 1; fi
  sleep 1
done
run_sql() {
  docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q < "$project_dir/$1"
}
run_sql supabase/tests/auth_fixture.sql
run_sql supabase/migrations/20261012021018_phase1_foundation.sql
run_sql supabase/migrations/20261012022056_first_supervisor_setup.sql
run_sql supabase/migrations/20261012131324_user_management.sql
run_sql supabase/migrations/20261012151246_pin_security.sql
run_sql supabase/migrations/20261012191936_agency_transfers.sql
run_sql supabase/migrations/20261012191938_operational_workflows.sql
run_sql supabase/migrations/20261013165018_personnel_usernames.sql
run_sql supabase/migrations/20261013165019_task_checklists.sql
run_sql supabase/migrations/20261018063737_account_code_handoff.sql
run_sql supabase/migrations/20261018063834_owner_account_erasure.sql
run_sql supabase/migrations/20261018072816_supervisor_schedule_deletion.sql
run_sql supabase/tests/schedule_deletion.sql
run_sql supabase/tests/account_code_handoff.sql
run_sql supabase/tests/owner_account_erasure.sql
run_sql supabase/tests/new_features.sql
run_sql supabase/tests/phase1_authorization.sql
run_sql supabase/tests/first_supervisor_setup.sql
run_sql supabase/tests/user_management.sql
run_sql supabase/migrations/20261018140000_admin_roles.sql
run_sql supabase/migrations/20261019030542_agency_supervisor_directory.sql
run_sql supabase/tests/agency_supervisor_directory.sql
run_sql supabase/tests/admin_roles.sql
run_sql supabase/tests/schedule_deletion.sql
run_sql supabase/tests/new_features.sql
run_sql supabase/tests/operational_workflows.sql
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -v keep_pin_fixture=1 -q \
  < "$project_dir/supabase/tests/pin_security.sql"
concurrency_log="$(mktemp)"
worker_pids=()
for attempt in {1..8}; do
  docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
    "select janitra_private.verify_pin('00000000-0000-0000-0000-000000000003','employee',
      '10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',repeat('d',64));" \
    >> "$concurrency_log" &
  worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do wait "$worker_pid"; done
incorrect_count=0
locked_count=0
while IFS= read -r result; do
  case "$result" in
    incorrect) ((incorrect_count+=1));;
    locked) ((locked_count+=1));;
    *) echo "FAIL: unexpected concurrent PIN outcome" >&2; exit 1;;
  esac
done < "$concurrency_log"
if [[ "$incorrect_count" != 4 || "$locked_count" != 4 ]]; then
  echo 'FAIL: concurrent attempts exceeded account limit' >&2; exit 1
fi
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q -c \
  "select public.test_assert((select failed_attempts=5 and locked_until>clock_timestamp()
    from janitra_private.employee_pin_credentials where user_id='00000000-0000-0000-0000-000000000003'),
    'concurrent attempts serialize and stop at five failures');"
echo 'PASS: migrations and authorization checks in isolated PostgreSQL; no remote changes'
run_sql supabase/tests/workflow_concurrency.sql
rm -f "$concurrency_log"
concurrency_log="$(mktemp)"
worker_pids=()
for action in approve reject; do
  docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
    "select public.workflow_command('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000901','$action',
      jsonb_build_object('request_id',gen_random_uuid(),'task_id','97000000-0000-0000-0000-000000000001','version',0,'reason','Test review'))->>'ok';" >> "$concurrency_log" &
  worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do wait "$worker_pid"; done
success_count=0
conflict_count=0
while IFS= read -r result; do
  case "$result" in
    true) ((success_count+=1));;
    false) ((conflict_count+=1));;
    *) echo 'FAIL: unexpected concurrent workflow result' >&2; exit 1;;
  esac
done < "$concurrency_log"
if [[ "$success_count" != 1 || "$conflict_count" != 1 ]]; then echo 'FAIL: concurrent approvals did not serialize'; exit 1; fi
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q -c \
  "select public.test_assert((select count(*)=1 from public.approval_events where task_id='97000000-0000-0000-0000-000000000001'),
    'concurrent approve/reject produce exactly one final event');"
echo 'PASS: concurrent workflow review and deadline boundary checks'
run_sql supabase/tests/identity_concurrency.sql
rm -f "$concurrency_log"
concurrency_log="$(mktemp)"
worker_pids=()
for attempt in {1..4}; do
  docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
    "select public.personnel_identity_command(null,null,'claim_grant',jsonb_build_object('identifier','race.person','digest',repeat('f',64))) ? 'claim_id';" >> "$concurrency_log" &
  worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do wait "$worker_pid"; done
success_count=0
denied_count=0
while IFS= read -r result; do
  case "$result" in
    t) ((success_count+=1));;
    f) ((denied_count+=1));;
    *) echo 'FAIL: unexpected concurrent recovery claim result' >&2; exit 1;;
  esac
done < "$concurrency_log"
if [[ "$success_count" != 1 || "$denied_count" != 3 ]]; then echo 'FAIL: recovery code had more than one claimant'; exit 1; fi
echo 'PASS: concurrent recovery redemption permits exactly one claimant'
run_sql supabase/tests/schedule_deletion_concurrency.sql
worker_pids=()
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
 "begin; select janitra_private.generate_work(current_date+1,current_date+1,'10000000-0000-0000-0000-000000000931'); select pg_sleep(0.4); commit;" >> "$concurrency_log" &
worker_pids+=("$!")
for attempt in {1..2}; do
 docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
  "select public.workflow_command('00000000-0000-0000-0000-000000000931','00000000-0000-0000-0000-000000000931','activity_delete',
   '{\"id\":\"40000000-0000-0000-0000-000000000931\",\"agency_id\":\"10000000-0000-0000-0000-000000000931\",\"site_id\":\"30000000-0000-0000-0000-000000000931\",\"request_id\":\"80000000-0000-0000-0000-000000000931\"}'::jsonb);" >> "$concurrency_log" &
 worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do wait "$worker_pid"; done
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q -c \
 "select public.test_assert(not exists(select 1 from public.task_instances where rule_id='60000000-0000-0000-0000-000000000931' and status='SCHEDULED'),
  'concurrent generation and deletion cannot leave active future tasks');
  select public.test_assert((select count(*)=1 from public.audit_events where entity_id='40000000-0000-0000-0000-000000000931' and action='delete'),
  'simultaneous repeated scheduling deletion records one result');"
echo 'PASS: concurrent generation and repeated schedule deletion'
run_sql supabase/tests/admin_concurrency.sql
rm -f "$concurrency_log"
concurrency_log="$(mktemp)"
worker_pids=()
for suffix in 961 962; do
 docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
  "select public.test_suspend_admin('00000000-0000-0000-0000-000000000$suffix');" >> "$concurrency_log" &
 worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do wait "$worker_pid"; done
success_count=0
denied_count=0
while IFS= read -r result; do
 case "$result" in
  t) ((success_count+=1));;
  f) ((denied_count+=1));;
  *) echo 'FAIL: unexpected Admin removal result' >&2; exit 1;;
 esac
done < "$concurrency_log"
if [[ "$success_count" != 1 || "$denied_count" != 1 ]]; then echo 'FAIL: last Admin race was not prevented'; exit 1; fi
echo 'PASS: concurrent Admin suspension preserves one active Admin'
run_sql supabase/migrations/20261019040713_company_wide_supervisors.sql
run_sql supabase/migrations/20261019043557_company_wide_agency_creation.sql
run_sql supabase/tests/company_wide_supervisors.sql
run_sql supabase/tests/company_wide_agency_creation.sql
run_sql supabase/tests/company_wide_concurrency.sql
for operation in workflow agency; do
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q -c \
 "update public.role_assignments set is_active=true where user_id='00000000-0000-0000-0000-000000001001';"
rm -f "$concurrency_log"
concurrency_log="$(mktemp)"
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -q -c \
 "set application_name='janitra-company-revoker'; begin;
  update public.role_assignments set is_active=false where user_id='00000000-0000-0000-0000-000000001001';
  select pg_sleep(3); commit;" >/dev/null &
revoker_pid=$!
for attempt in {1..30}; do
 ready=$(docker exec "$container_name" psql -U postgres -Atq -c "select exists(select 1 from pg_stat_activity where application_name='janitra-company-revoker' and wait_event='PgSleep');")
 if [[ "$ready" == t ]]; then break; fi
 sleep 0.05
done
if [[ "$ready" != t ]]; then echo 'FAIL: scope revoker did not acquire its lock'; exit 1; fi
docker exec "$container_name" psql -U postgres -v ON_ERROR_STOP=1 -Atq -c \
 "set application_name='janitra-company-writer'; select public.test_company_scope_write('$operation'='agency');" > "$concurrency_log" &
writer_pid=$!
for attempt in {1..30}; do
 waiting=$(docker exec "$container_name" psql -U postgres -Atq -c "select exists(select 1 from pg_stat_activity where application_name='janitra-company-writer' and wait_event_type='Lock');")
 if [[ "$waiting" == t ]]; then break; fi
 sleep 0.05
done
if [[ "$waiting" != t ]]; then echo 'FAIL: cross-company mutation did not wait for the authority lock'; exit 1; fi
echo "PASS: $operation mutation waits on concurrent Company-Wide revocation"
wait "$revoker_pid"
wait "$writer_pid"
result=$(< "$concurrency_log")
unchanged=$(docker exec "$container_name" psql -U postgres -Atq -c "select not exists(select 1 from public.work_activities where id='40000000-0000-0000-0000-000000001001') and not exists(select 1 from public.agencies where name='Revoked creation must not exist');")
if [[ "$result" != denied || "$unchanged" != t ]]; then echo 'FAIL: revoked Company-Wide mutation was accepted'; exit 1; fi
echo "PASS: confirmed Company-Wide revocation denies the waiting $operation mutation without writing data"
done
run_sql supabase/migrations/20261019210136_admin_unassigned_accounts.sql
run_sql supabase/tests/admin_unassigned_accounts.sql
run_sql supabase/tests/account_code_handoff.sql
