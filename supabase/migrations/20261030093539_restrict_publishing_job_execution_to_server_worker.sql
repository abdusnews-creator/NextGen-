CREATE OR REPLACE FUNCTION public.guard_publishing_job_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.status IN ('processing','published')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND coalesce(auth.role(),'') <> 'service_role' THEN
    RAISE EXCEPTION 'Only a verified server-side worker can process or publish a queued job' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS publishing_jobs_server_status_only ON public.publishing_jobs;
CREATE TRIGGER publishing_jobs_server_status_only
BEFORE UPDATE OF status ON public.publishing_jobs
FOR EACH ROW EXECUTE FUNCTION public.guard_publishing_job_status();


