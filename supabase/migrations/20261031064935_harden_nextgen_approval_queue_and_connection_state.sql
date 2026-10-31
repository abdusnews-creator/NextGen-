-- NextGen backend hardening: keep approvals auditable, queue mutations constrained,
-- and connection/background states truthful until trusted server-side workers exist.

-- Content may be created and edited by its owner while unapproved. Only the
-- authenticated review RPC can approve/reject, and only the scheduling RPC can
-- move approved content into the queue.
DROP POLICY IF EXISTS "owners manage their content" ON public.content_items;
DROP POLICY IF EXISTS "nextgen owners read content" ON public.content_items;
DROP POLICY IF EXISTS "nextgen owners insert unapproved content" ON public.content_items;
DROP POLICY IF EXISTS "nextgen owners update unapproved content" ON public.content_items;
DROP POLICY IF EXISTS "nextgen owners delete unapproved content" ON public.content_items;

CREATE POLICY "nextgen owners read content"
  ON public.content_items FOR SELECT TO authenticated
  USING ((select auth.uid()) = owner_id);

CREATE POLICY "nextgen owners insert unapproved content"
  ON public.content_items FOR INSERT TO authenticated
  WITH CHECK (
    (select auth.uid()) = owner_id
    AND status IN ('draft','pending_approval')
    AND approved_at IS NULL
    AND approved_by IS NULL
  );

CREATE POLICY "nextgen owners update unapproved content"
  ON public.content_items FOR UPDATE TO authenticated
  USING (
    (select auth.uid()) = owner_id
    AND status IN ('draft','pending_approval','rejected')
  )
  WITH CHECK (
    (select auth.uid()) = owner_id
    AND status IN ('draft','pending_approval','rejected')
    AND approved_at IS NULL
    AND approved_by IS NULL
  );

CREATE POLICY "nextgen owners delete unapproved content"
  ON public.content_items FOR DELETE TO authenticated
  USING (
    (select auth.uid()) = owner_id
    AND status IN ('draft','pending_approval','rejected')
  );

-- Approval history is append-only for browser clients. The SECURITY DEFINER
-- review RPC writes events after checking the caller and content owner.
DROP POLICY IF EXISTS "owners manage their approval events" ON public.approval_events;
DROP POLICY IF EXISTS "nextgen owners read approval events" ON public.approval_events;
CREATE POLICY "nextgen owners read approval events"
  ON public.approval_events FOR SELECT TO authenticated
  USING ((select auth.uid()) = owner_id);

-- Browser clients may view jobs and cancel their own queued jobs only. They
-- cannot create, delete, process, publish, or rewrite the contents of a job.
DROP POLICY IF EXISTS "owners manage their publishing jobs" ON public.publishing_jobs;
DROP POLICY IF EXISTS "nextgen owners read publishing jobs" ON public.publishing_jobs;
DROP POLICY IF EXISTS "nextgen owners cancel queued jobs" ON public.publishing_jobs;
CREATE POLICY "nextgen owners read publishing jobs"
  ON public.publishing_jobs FOR SELECT TO authenticated
  USING ((select auth.uid()) = owner_id);
CREATE POLICY "nextgen owners cancel queued jobs"
  ON public.publishing_jobs FOR UPDATE TO authenticated
  USING ((select auth.uid()) = owner_id AND status = 'queued')
  WITH CHECK ((select auth.uid()) = owner_id AND status = 'cancelled');

-- Remove broad default grants and restore only the browser operations used by
-- NextGen. RLS policies above remain the row-level boundary.
REVOKE ALL ON TABLE public.content_items, public.approval_events,
  public.publishing_jobs, public.platform_connections, public.automation_settings
  FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.content_items TO authenticated;
GRANT SELECT ON public.approval_events TO authenticated;
GRANT SELECT, UPDATE ON public.publishing_jobs TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.platform_connections TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.automation_settings TO authenticated;
REVOKE ALL ON TABLE public.channels,
  public.channel_analytics_daily, public.content_analytics_daily,
  public.notification_preferences, public.activity_logs
  FROM anon;

-- These RPCs must perform their own auth.uid()/owner checks because they now
-- cross the stricter browser RLS policies.
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

-- A user may cancel a queued job, but cannot mutate its payload or move it into
-- processing/published states. The scheduling RPC may insert queued jobs;
-- direct browser INSERT/DELETE is denied by grants and RLS.
CREATE OR REPLACE FUNCTION public.guard_publishing_job_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF coalesce(auth.role(),'') = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'queued' THEN
      RAISE EXCEPTION 'Only the server worker can create non-queued publishing jobs' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status <> 'queued' OR NEW.status <> 'cancelled' THEN
    RAISE EXCEPTION 'Users may only cancel queued publishing jobs' USING ERRCODE = '42501';
  END IF;

  IF ROW(
    NEW.id, NEW.owner_id, NEW.content_id, NEW.channel_id, NEW.scheduled_for,
    NEW.attempt_count, NEW.max_attempts, NEW.next_attempt_at,
    NEW.external_post_id, NEW.last_error, NEW.started_at, NEW.completed_at, NEW.created_at
  ) IS DISTINCT FROM ROW(
    OLD.id, OLD.owner_id, OLD.content_id, OLD.channel_id, OLD.scheduled_for,
    OLD.attempt_count, OLD.max_attempts, OLD.next_attempt_at,
    OLD.external_post_id, OLD.last_error, OLD.started_at, OLD.completed_at, OLD.created_at
  ) THEN
    RAISE EXCEPTION 'Queued job details are immutable; cancel and create a new approved schedule' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS publishing_jobs_server_status_only ON public.publishing_jobs;
CREATE TRIGGER publishing_jobs_server_status_only
BEFORE INSERT OR UPDATE OF status ON public.publishing_jobs
FOR EACH ROW EXECUTE FUNCTION public.guard_publishing_job_status();

-- A browser-supplied status is not proof of an OAuth connection. Only a
-- trusted server-side OAuth callback may mark either record as connected.
CREATE OR REPLACE FUNCTION public.guard_verified_connection_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.connection_status = 'connected'
     AND coalesce(auth.role(),'') <> 'service_role' THEN
    RAISE EXCEPTION 'Only a verified server-side OAuth callback can mark a platform connection as connected' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS channels_verified_connection_only ON public.channels;
CREATE TRIGGER channels_verified_connection_only
BEFORE INSERT OR UPDATE OF connection_status ON public.channels
FOR EACH ROW EXECUTE FUNCTION public.guard_verified_connection_status();

DROP TRIGGER IF EXISTS platform_connections_verified_connection_only ON public.platform_connections;
CREATE TRIGGER platform_connections_verified_connection_only
BEFORE INSERT OR UPDATE OF connection_status ON public.platform_connections
FOR EACH ROW EXECUTE FUNCTION public.guard_verified_connection_status();

-- No background worker or pg_cron scheduler is deployed yet. Clear the stale
-- preference and keep browser clients from claiming background mode is live.
UPDATE public.automation_settings
SET background_mode_enabled = false
WHERE background_mode_enabled IS DISTINCT FROM false;

CREATE OR REPLACE FUNCTION public.guard_background_mode_setting()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.background_mode_enabled
     AND coalesce(auth.role(),'') <> 'service_role' THEN
    RAISE EXCEPTION 'Background mode stays disabled until a server-side worker is deployed and verified' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS automation_settings_background_mode_guard ON public.automation_settings;
CREATE TRIGGER automation_settings_background_mode_guard
BEFORE INSERT OR UPDATE OF background_mode_enabled ON public.automation_settings
FOR EACH ROW EXECUTE FUNCTION public.guard_background_mode_setting();
