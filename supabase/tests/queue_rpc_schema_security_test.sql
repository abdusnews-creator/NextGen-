\set ON_ERROR_STOP on
DO $$
DECLARE
BEGIN

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='review_content_item'
      AND p.prosecdef=false
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='schedule_approved_content'
      AND p.prosecdef=false
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='cancel_scheduled_content'
      AND p.prosecdef=false
  ) THEN
    RAISE EXCEPTION 'Public PostgREST RPC endpoints must be SECURITY INVOKER';
  END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='nextgen_private'
        AND p.proname IN ('review_content_item','schedule_approved_content','cancel_scheduled_content')
        AND p.prosecdef=true) <> 3 THEN
    RAISE EXCEPTION 'All three privileged implementations must remain SECURITY DEFINER in private schema';
  END IF;

  IF has_schema_privilege('anon','nextgen_private','USAGE') OR EXISTS (
    SELECT 1 FROM pg_namespace n,
      LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
    WHERE n.nspname='nextgen_private' AND a.grantee=0 AND a.privilege_type='USAGE'
  ) THEN
    RAISE EXCEPTION 'Private schema must not be accessible to anon or PUBLIC';
  END IF;

  IF NOT has_schema_privilege('authenticated','nextgen_private','USAGE') THEN
    RAISE EXCEPTION 'Authenticated role needs schema usage for invoker wrappers';
  END IF;

  IF NOT has_function_privilege('authenticated','public.review_content_item(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.schedule_approved_content(uuid,uuid,timestamp with time zone)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.cancel_scheduled_content(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated role lost access to stable public RPC wrappers';
  END IF;

  IF has_function_privilege('anon','public.review_content_item(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.schedule_approved_content(uuid,uuid,timestamp with time zone)','EXECUTE')
     OR has_function_privilege('anon','public.cancel_scheduled_content(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Anon must not execute privileged RPC wrappers';
  END IF;
END $$;
