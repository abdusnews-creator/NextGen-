-- Keep privileged implementation details out of the exposed PostgREST schema.
-- Public RPC names remain stable, but are SECURITY INVOKER wrappers. The actual
-- owner-checked SECURITY DEFINER implementations live in a non-exposed schema.

CREATE SCHEMA IF NOT EXISTS nextgen_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA nextgen_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA nextgen_private TO authenticated;

ALTER FUNCTION public.review_content_item(uuid,text,text) SET SCHEMA nextgen_private;
ALTER FUNCTION public.schedule_approved_content(uuid,uuid,timestamptz) SET SCHEMA nextgen_private;
ALTER FUNCTION public.cancel_scheduled_content(uuid,text) SET SCHEMA nextgen_private;

-- Use an empty search_path for privileged implementations. All application
-- relations and auth helpers in these function bodies are schema-qualified.
ALTER FUNCTION nextgen_private.review_content_item(uuid,text,text) SET search_path = '';
ALTER FUNCTION nextgen_private.schedule_approved_content(uuid,uuid,timestamptz) SET search_path = '';
ALTER FUNCTION nextgen_private.cancel_scheduled_content(uuid,text) SET search_path = '';

REVOKE ALL ON FUNCTION nextgen_private.review_content_item(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION nextgen_private.schedule_approved_content(uuid,uuid,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION nextgen_private.cancel_scheduled_content(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION nextgen_private.review_content_item(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION nextgen_private.schedule_approved_content(uuid,uuid,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION nextgen_private.cancel_scheduled_content(uuid,text) TO authenticated;

-- Cancellation must go through the audited RPC. The older browser policy and
-- table grant allowed direct queued -> cancelled updates, which bypassed the
-- audit event and content-state restoration performed by cancel_scheduled_content.
DROP POLICY IF EXISTS "nextgen owners cancel queued jobs" ON public.publishing_jobs;
REVOKE UPDATE ON TABLE public.publishing_jobs FROM PUBLIC, anon, authenticated;

-- Stable PostgREST endpoints. These wrappers execute as the caller; the
-- narrowly-scoped private functions perform their own auth.uid()/owner checks.
CREATE OR REPLACE FUNCTION public.review_content_item(
  p_content_id uuid,
  p_action text,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT nextgen_private.review_content_item(p_content_id,p_action,p_note);
$$;

CREATE OR REPLACE FUNCTION public.schedule_approved_content(
  p_content_id uuid,
  p_channel_id uuid,
  p_scheduled_for timestamptz
) RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT nextgen_private.schedule_approved_content(p_content_id,p_channel_id,p_scheduled_for);
$$;

CREATE OR REPLACE FUNCTION public.cancel_scheduled_content(
  p_job_id uuid,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT nextgen_private.cancel_scheduled_content(p_job_id,p_note);
$$;

REVOKE ALL ON FUNCTION public.review_content_item(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.schedule_approved_content(uuid,uuid,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_scheduled_content(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_content_item(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_approved_content(uuid,uuid,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_scheduled_content(uuid,text) TO authenticated;
