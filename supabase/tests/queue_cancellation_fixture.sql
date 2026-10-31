-- Minimal isolated PostgreSQL fixture for queue-cancellation integration tests.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.role', true), '')
$$;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT EXECUTE ON FUNCTION auth.role() TO authenticated;

CREATE TABLE public.channels (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  platform text NOT NULL DEFAULT 'youtube',
  is_paused boolean NOT NULL DEFAULT false,
  UNIQUE (id, owner_id)
);
CREATE TABLE public.content_items (
  id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  channel_id uuid,
  status text NOT NULL,
  platform text NOT NULL DEFAULT 'youtube',
  approved_at timestamptz,
  approved_by uuid,
  rejection_reason text,
  scheduled_for timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, owner_id),
  FOREIGN KEY (channel_id, owner_id) REFERENCES public.channels(id, owner_id)
);
CREATE TABLE public.approval_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  content_id uuid NOT NULL REFERENCES public.content_items(id),
  action text NOT NULL CHECK (action IN ('submitted','approved','rejected','returned_for_edit')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.publishing_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id),
  content_id uuid NOT NULL,
  channel_id uuid NOT NULL,
  scheduled_for timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN ('queued','processing','published','failed','cancelled')),
  attempt_count integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3,
  next_attempt_at timestamptz,
  external_post_id text,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (content_id, owner_id) REFERENCES public.content_items(id, owner_id),
  FOREIGN KEY (channel_id, owner_id) REFERENCES public.channels(id, owner_id)
);

-- Match the production guard trigger that constrains browser job status updates.
CREATE OR REPLACE FUNCTION public.guard_publishing_job_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF coalesce(auth.role(),'') = 'service_role' THEN RETURN NEW; END IF;
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
CREATE TRIGGER publishing_jobs_server_status_only
BEFORE INSERT OR UPDATE OF status ON public.publishing_jobs
FOR EACH ROW EXECUTE FUNCTION public.guard_publishing_job_status();

GRANT SELECT ON public.channels, public.content_items, public.approval_events, public.publishing_jobs TO authenticated;
GRANT UPDATE ON public.content_items, public.channels TO authenticated;
GRANT INSERT ON public.publishing_jobs TO authenticated;
