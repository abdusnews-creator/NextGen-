\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(id) VALUES
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222');
INSERT INTO public.channels(id,owner_id) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222');

-- Owner cancels own exact queued schedule; content returns to approved and audit is written.
INSERT INTO public.content_items(id,owner_id,channel_id,status,scheduled_for) VALUES
 ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','scheduled','2030-01-01 08:00:00+00');
INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status) VALUES
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1','11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-8ccc-ccccccccccc1','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2030-01-01 08:00:00+00','queued');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.cancel_scheduled_content('dddddddd-dddd-4ddd-8ddd-ddddddddddd1','CI owner cancellation');

DO $$
BEGIN
  IF (SELECT status FROM public.publishing_jobs WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> 'cancelled' THEN
    RAISE EXCEPTION 'queued job was not cancelled';
  END IF;
  IF (SELECT status FROM public.content_items WHERE id='cccccccc-cccc-4ccc-8ccc-ccccccccccc1') <> 'approved'
     OR (SELECT scheduled_for FROM public.content_items WHERE id='cccccccc-cccc-4ccc-8ccc-ccccccccccc1') IS NOT NULL THEN
    RAISE EXCEPTION 'content was not restored to approved';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.approval_events WHERE content_id='cccccccc-cccc-4ccc-8ccc-ccccccccccc1' AND action='cancelled') THEN
    RAISE EXCEPTION 'cancel audit event missing';
  END IF;
END $$;

-- Owner A cannot cancel owner B's job.
INSERT INTO public.content_items(id,owner_id,channel_id,status,scheduled_for) VALUES
 ('cccccccc-cccc-4ccc-8ccc-ccccccccccc2','22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','scheduled','2030-01-02 08:00:00+00');
INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status) VALUES
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2','22222222-2222-4222-8222-222222222222','cccccccc-cccc-4ccc-8ccc-ccccccccccc2','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','2030-01-02 08:00:00+00','queued');
DO $$
BEGIN
  PERFORM public.cancel_scheduled_content('dddddddd-dddd-4ddd-8ddd-ddddddddddd2',NULL);
  RAISE EXCEPTION 'cross-owner cancellation unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
END $$;
RESET ROLE;
DO $$
BEGIN
  IF (SELECT status FROM public.publishing_jobs WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd2') <> 'queued' THEN
    RAISE EXCEPTION 'cross-owner attempt changed other owner job';
  END IF;
END $$;

-- A second active job prevents resetting the content item.
INSERT INTO public.content_items(id,owner_id,channel_id,status,scheduled_for) VALUES
 ('cccccccc-cccc-4ccc-8ccc-ccccccccccc3','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','scheduled','2030-01-03 08:00:00+00');
INSERT INTO public.publishing_jobs(id,owner_id,content_id,channel_id,scheduled_for,status) VALUES
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3','11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-8ccc-ccccccccccc3','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2030-01-03 08:00:00+00','queued'),
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4','11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-8ccc-ccccccccccc3','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2030-01-04 08:00:00+00','queued');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.cancel_scheduled_content('dddddddd-dddd-4ddd-8ddd-ddddddddddd3',NULL);
RESET ROLE;
DO $$
BEGIN
  IF (SELECT status FROM public.content_items WHERE id='cccccccc-cccc-4ccc-8ccc-ccccccccccc3') <> 'scheduled' THEN
    RAISE EXCEPTION 'content reset despite another active job';
  END IF;
END $$;

-- Processing jobs cannot be cancelled.
SELECT set_config('request.jwt.claim.role','service_role',true);
UPDATE public.publishing_jobs SET status='processing'
WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd4';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $$
BEGIN
  PERFORM public.cancel_scheduled_content('dddddddd-dddd-4ddd-8ddd-ddddddddddd4',NULL);
  RAISE EXCEPTION 'processing job cancellation unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
END $$;
RESET ROLE;

ROLLBACK;
