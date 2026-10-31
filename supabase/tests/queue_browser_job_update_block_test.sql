\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(id)
VALUES ('51111111-1111-4111-8111-111111111111');

INSERT INTO public.channels(id,owner_id,platform,is_paused)
VALUES ('5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','51111111-1111-4111-8111-111111111111','youtube',false);

INSERT INTO public.content_items(id,owner_id,channel_id,status,platform,scheduled_for)
VALUES ('5ccccccc-cccc-4ccc-8ccc-cccccccccc01',
        '51111111-1111-4111-8111-111111111111',
        '5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'scheduled','youtube','2030-04-01 08:00:00+00');

INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status)
VALUES ('5ddddddd-dddd-4ddd-8ddd-dddddddddd01',
        '51111111-1111-4111-8111-111111111111',
        '5ccccccc-cccc-4ccc-8ccc-cccccccccc01',
        '5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        '2030-04-01 08:00:00+00','queued');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','51111111-1111-4111-8111-111111111111',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);

DO $$
BEGIN
  UPDATE public.publishing_jobs
  SET status='cancelled'
  WHERE id='5ddddddd-dddd-4ddd-8ddd-dddddddddd01';

  RAISE EXCEPTION 'Direct browser cancellation unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE '42501' THEN
  NULL;
END $$;

RESET ROLE;

DO $$
BEGIN
  IF (SELECT status FROM public.publishing_jobs
      WHERE id='5ddddddd-dddd-4ddd-8ddd-dddddddddd01') <> 'queued' THEN
    RAISE EXCEPTION 'Direct browser attempt changed the publishing job';
  END IF;

  IF (SELECT count(*) FROM public.approval_events
      WHERE content_id='5ccccccc-cccc-4ccc-8ccc-cccccccccc01'
        AND action='cancelled') <> 0 THEN
    RAISE EXCEPTION 'Direct browser attempt unexpectedly created a cancellation audit event';
  END IF;
END $$;

ROLLBACK;

