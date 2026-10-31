#!/usr/bin/env bash
set -euo pipefail

owner="11111111-1111-4111-8111-111111111111"
channel="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
content="cccccccc-cccc-4ccc-8ccc-cccccccccc91"
job="dddddddd-dddd-4ddd-8ddd-dddddddddd91"
first_log="$(mktemp)"
second_log="$(mktemp)"
trap 'rm -f "$first_log" "$second_log"' EXIT

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO auth.users(id) VALUES ('$owner') ON CONFLICT DO NOTHING;
INSERT INTO public.channels(id,owner_id) VALUES ('$channel','$owner') ON CONFLICT DO NOTHING;
INSERT INTO public.content_items(id,owner_id,channel_id,status,scheduled_for)
VALUES ('$content','$owner','$channel','scheduled','2030-02-01 08:00:00+00');
INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status)
VALUES ('$job','$owner','$content','$channel','2030-02-01 08:00:00+00','queued');
SQL

# Session one wins the cancellation and deliberately holds its row locks briefly.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >"$first_log" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$owner',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.cancel_scheduled_content('$job','concurrency winner');
SELECT pg_sleep(2);
COMMIT;
SQL
first_pid=$!

# Let session one enter the RPC before the competing request starts.
sleep 0.25
set +e
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >"$second_log" 2>&1 <<SQL
\\set VERBOSITY verbose
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$owner',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.cancel_scheduled_content('$job','concurrency loser');
COMMIT;
SQL
second_status=$?
set -e
wait "$first_pid"

if [ "$second_status" -eq 0 ]; then
  echo "ERROR: competing cancellation unexpectedly succeeded"
  cat "$second_log"
  exit 1
fi
if ! grep -q "55000" "$second_log"; then
  echo "ERROR: competing request failed for an unexpected reason"
  cat "$second_log"
  exit 1
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF (SELECT status FROM public.publishing_jobs WHERE id='$job') <> 'cancelled' THEN
    RAISE EXCEPTION 'winning cancellation did not persist';
  END IF;
  IF (SELECT status FROM public.content_items WHERE id='$content') <> 'approved' THEN
    RAISE EXCEPTION 'content was not restored exactly once';
  END IF;
  IF (SELECT count(*) FROM public.approval_events WHERE content_id='$content' AND action='cancelled') <> 1 THEN
    RAISE EXCEPTION 'expected exactly one cancellation audit event';
  END IF;
END
\\$\$;
SQL

echo "PASS: concurrent cancellation serialized; one success, one 55000 rejection, one audit event."
