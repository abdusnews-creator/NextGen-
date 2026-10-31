#!/usr/bin/env bash
set -euo pipefail

owner="31111111-1111-4111-8111-111111111111"
channel="3aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
content="3ccccccc-cccc-4ccc-8ccc-cccccccccc91"
old_job="3ddddddd-dddd-4ddd-8ddd-dddddddddd91"
old_time="2030-03-01 08:00:00+00"
new_time="2030-03-02 14:00:00+00"
cancel_log="$(mktemp)"
schedule_log="$(mktemp)"
trap 'rm -f "$cancel_log" "$schedule_log"' EXIT

# Seed a realistic queued schedule. The job insert guard requires approved
# content, so create the queued job first and then reflect its scheduled state.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users(id) VALUES ('$owner');
INSERT INTO public.channels(id,owner_id,platform,is_paused)
VALUES ('$channel','$owner','youtube',false);
INSERT INTO public.content_items(id,owner_id,channel_id,status,platform)
VALUES ('$content','$owner','$channel','approved','youtube');
INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status)
VALUES ('$old_job','$owner','$content','$channel','$old_time','queued');
UPDATE public.content_items
SET status='scheduled', scheduled_for='$old_time'
WHERE id='$content';
SQL

# Cancellation obtains the content lock, resets it to approved, then pauses
# before commit so the concurrent schedule RPC must wait on the same row.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >"$cancel_log" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$owner',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.cancel_scheduled_content('$old_job','cancel then reschedule race');
SELECT pg_sleep(2);
COMMIT;
SQL
cancel_pid=$!

sleep 0.25
set +e
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >"$schedule_log" 2>&1 <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$owner',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.schedule_approved_content('$content','$channel','$new_time');
COMMIT;
SQL
schedule_status=$?
set -e
wait "$cancel_pid"

if [ "$schedule_status" -ne 0 ]; then
  echo "ERROR: schedule RPC did not succeed after cancellation committed"
  cat "$schedule_log"
  cat "$cancel_log"
  exit 1
fi

checks="$(psql "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "
SELECT (SELECT status FROM public.publishing_jobs WHERE id='$old_job') = 'cancelled';
SELECT (SELECT status FROM public.content_items WHERE id='$content') = 'scheduled';
SELECT (SELECT scheduled_for FROM public.content_items WHERE id='$content') = '$new_time'::timestamptz;
SELECT (SELECT count(*) FROM public.publishing_jobs WHERE content_id='$content' AND status='queued') = 1;
SELECT (SELECT count(*) FROM public.approval_events WHERE content_id='$content' AND action='cancelled') = 1;
")"
printf '%s\n' "$checks"
if [ "$checks" != $'t\nt\nt\nt\nt' ]; then
  echo "ERROR: schedule/cancel race left an unexpected final state"
  cat "$schedule_log"
  cat "$cancel_log"
  exit 1
fi

echo "PASS: cancellation and rescheduling serialize; new approved schedule survives with one active job and one cancellation audit event."
