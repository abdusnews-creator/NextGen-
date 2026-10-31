-- Allow owners to cancel a queued schedule through an audited, atomic workflow.
-- The content item returns to approved only when this job is still its active
-- schedule and no other queued/processing job exists for the same content.

ALTER TABLE public.approval_events
  DROP CONSTRAINT IF EXISTS approval_events_action_check;

ALTER TABLE public.approval_events
  ADD CONSTRAINT approval_events_action_check
  CHECK (action IN ('submitted','approved','rejected','returned_for_edit','cancelled'));

CREATE OR REPLACE FUNCTION public.cancel_scheduled_content(
  p_job_id uuid,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_job public.publishing_jobs%ROWTYPE;
  v_item public.content_items%ROWTYPE;
  v_restored boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  -- Read the owner-scoped job identity first, then lock content before job.
  -- This follows the same content -> job lock order used by scheduling.
  SELECT * INTO v_job
  FROM public.publishing_jobs
  WHERE id = p_job_id AND owner_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Scheduled job not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_item
  FROM public.content_items
  WHERE id = v_job.content_id AND owner_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Content item not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_job
  FROM public.publishing_jobs
  WHERE id = p_job_id
    AND owner_id = v_user_id
    AND content_id = v_item.id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Scheduled job not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_job.status <> 'queued' THEN
    RAISE EXCEPTION 'Only queued schedules can be cancelled' USING ERRCODE = '55000';
  END IF;

  UPDATE public.publishing_jobs
  SET status = 'cancelled',
      updated_at = now()
  WHERE id = v_job.id AND owner_id = v_user_id;

  -- Restore the content only if it still reflects this exact schedule and
  -- there is no other active job. Never overwrite a newer schedule.
  IF v_item.status = 'scheduled'
     AND v_item.scheduled_for IS NOT DISTINCT FROM v_job.scheduled_for
     AND v_item.channel_id IS NOT DISTINCT FROM v_job.channel_id
     AND NOT EXISTS (
       SELECT 1
       FROM public.publishing_jobs active_job
       WHERE active_job.content_id = v_item.id
         AND active_job.owner_id = v_user_id
         AND active_job.id <> v_job.id
         AND active_job.status IN ('queued','processing')
     ) THEN
    UPDATE public.content_items
    SET status = 'approved',
        scheduled_for = NULL,
        updated_at = now()
    WHERE id = v_item.id
      AND owner_id = v_user_id
      AND status = 'scheduled';

    v_restored := FOUND;
  END IF;

  INSERT INTO public.approval_events(owner_id, content_id, action, note)
  VALUES (
    v_user_id,
    v_item.id,
    'cancelled',
    nullif(left(coalesce(p_note, 'Schedule cancelled by owner'), 1000), '')
  );

  RETURN jsonb_build_object(
    'ok', true,
    'job_id', v_job.id,
    'job_status', 'cancelled',
    'content_restored_to_approved', v_restored
  );
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_scheduled_content(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_scheduled_content(uuid,text) TO authenticated;
