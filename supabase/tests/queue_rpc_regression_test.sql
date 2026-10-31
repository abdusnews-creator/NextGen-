\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(id) VALUES
 ('41111111-1111-4111-8111-111111111111'),
 ('42222222-2222-4222-8222-222222222222');

INSERT INTO public.content_items(id,owner_id,status,platform) VALUES
 ('4ccccccc-cccc-4ccc-8ccc-cccccccccc01','41111111-1111-4111-8111-111111111111','pending_approval','youtube'),
 ('4ccccccc-cccc-4ccc-8ccc-cccccccccc02','41111111-1111-4111-8111-111111111111','pending_approval','youtube'),
 ('4ccccccc-cccc-4ccc-8ccc-cccccccccc03','42222222-2222-4222-8222-222222222222','pending_approval','youtube');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','41111111-1111-4111-8111-111111111111',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);

-- Owner can explicitly approve content and gets an immutable audit event.
SELECT public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc01','approved','manual owner approval');

DO $$
BEGIN
  IF (SELECT status FROM public.content_items WHERE id='4ccccccc-cccc-4ccc-8ccc-cccccccccc01') <> 'approved'
     OR (SELECT approved_by FROM public.content_items WHERE id='4ccccccc-cccc-4ccc-8ccc-cccccccccc01') <> '41111111-1111-4111-8111-111111111111'::uuid
     OR (SELECT approved_at FROM public.content_items WHERE id='4ccccccc-cccc-4ccc-8ccc-cccccccccc01') IS NULL THEN
    RAISE EXCEPTION 'manual approval did not set expected owner and timestamp';
  END IF;
  IF (SELECT count(*) FROM public.approval_events WHERE content_id='4ccccccc-cccc-4ccc-8ccc-cccccccccc01' AND action='approved') <> 1 THEN
    RAISE EXCEPTION 'approval audit event missing or duplicated';
  END IF;
END $$;

-- Owner can reject pending content with a bounded reason and audit event.
SELECT public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc02','rejected',repeat('r',1500));
DO $$
BEGIN
  IF (SELECT status FROM public.content_items WHERE id='4ccccccc-cccc-4ccc-8ccc-cccccccccc02') <> 'rejected'
     OR (SELECT length(rejection_reason) FROM public.content_items WHERE id='4ccccccc-cccc-4ccc-8ccc-cccccccccc02') <> 1000 THEN
    RAISE EXCEPTION 'rejection state or reason bound is incorrect';
  END IF;
  IF (SELECT count(*) FROM public.approval_events WHERE content_id='4ccccccc-cccc-4ccc-8ccc-cccccccccc02' AND action='rejected') <> 1 THEN
    RAISE EXCEPTION 'rejection audit event missing or duplicated';
  END IF;
END $$;

-- Owner cannot review another owner's content.
DO $$
BEGIN
  PERFORM public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc03','approved',NULL);
  RAISE EXCEPTION 'cross-owner review unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
END $$;

-- A second review cannot overwrite a final decision.
DO $$
BEGIN
  PERFORM public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc01','rejected','attempt to reverse');
  RAISE EXCEPTION 'already approved content was reviewed again';
EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
END $$;

-- Invalid actions are rejected.
DO $$
BEGIN
  PERFORM public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc01','published',NULL);
  RAISE EXCEPTION 'invalid review action unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub','',true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM public.review_content_item('4ccccccc-cccc-4ccc-8ccc-cccccccccc01','approved',NULL);
  RAISE EXCEPTION 'unauthenticated review unexpectedly succeeded';
EXCEPTION WHEN SQLSTATE '28000' THEN NULL;
END $$;

ROLLBACK;
