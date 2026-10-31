-- Test-only snapshot of the production SECURITY DEFINER RPC definitions
-- from 20261031064935_harden_nextgen_approval_queue_and_connection_state.sql.
-- Keeps isolated PostgreSQL CI aligned with the live production execution mode.

CREATE OR REPLACE FUNCTION public.review_content_item(
  p_content_id uuid,
  p_action text,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item public.content_items%ROWTYPE;
  v_status text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  IF p_action NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Action must be approved or rejected' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_item
  FROM public.content_items
  WHERE id = p_content_id AND owner_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Content item not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_item.status NOT IN ('draft','pending_approval') THEN
    RAISE EXCEPTION 'Only draft or pending approval content can be reviewed' USING ERRCODE = '55000';
  END IF;

  v_status := CASE WHEN p_action = 'approved' THEN 'approved' ELSE 'rejected' END;

  UPDATE public.content_items
  SET status = v_status,
      approved_at = CASE WHEN p_action = 'approved' THEN now() ELSE NULL END,
      approved_by = CASE WHEN p_action = 'approved' THEN v_user_id ELSE NULL END,
      rejection_reason = CASE WHEN p_action = 'rejected' THEN left(coalesce(p_note,''),1000) ELSE NULL END,
      updated_at = now()
  WHERE id = p_content_id AND owner_id = v_user_id;

  INSERT INTO public.approval_events(owner_id, content_id, action, note)
  VALUES (v_user_id, p_content_id, p_action, nullif(left(coalesce(p_note,''),1000),''));

  RETURN jsonb_build_object('ok',true,'content_id',p_content_id,'status',v_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_approved_content(
  p_content_id uuid,
  p_channel_id uuid,
  p_scheduled_for timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item public.content_items%ROWTYPE;
  v_channel public.channels%ROWTYPE;
  v_job public.publishing_jobs%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  IF p_scheduled_for IS NULL OR p_scheduled_for <= now() THEN
    RAISE EXCEPTION 'Choose a future schedule time' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_item
  FROM public.content_items
  WHERE id = p_content_id AND owner_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Content item not found' USING ERRCODE = 'P0002'; END IF;
  IF v_item.status <> 'approved' THEN
    RAISE EXCEPTION 'Only explicitly approved content can be scheduled' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_channel
  FROM public.channels
  WHERE id = p_channel_id AND owner_id = v_user_id
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Channel not found for this account' USING ERRCODE = 'P0002'; END IF;
  IF v_channel.is_paused THEN RAISE EXCEPTION 'This channel is paused' USING ERRCODE = '55000'; END IF;
  IF v_channel.platform <> v_item.platform THEN
    RAISE EXCEPTION 'The selected channel platform does not match this content' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.publishing_jobs(owner_id,content_id,channel_id,scheduled_for,status)
  VALUES (v_user_id,p_content_id,p_channel_id,p_scheduled_for,'queued')
  RETURNING * INTO v_job;

  UPDATE public.content_items
  SET channel_id = p_channel_id, scheduled_for = p_scheduled_for,
      status = 'scheduled', updated_at = now()
  WHERE id = p_content_id AND owner_id = v_user_id;

  RETURN jsonb_build_object('ok',true,'job_id',v_job.id,'status','queued',
    'message','Scheduled in NextGen queue only. No platform publishing was performed.');
END;
$$;

REVOKE ALL ON FUNCTION public.review_content_item(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.schedule_approved_content(uuid,uuid,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_content_item(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_approved_content(uuid,uuid,timestamptz) TO authenticated;
