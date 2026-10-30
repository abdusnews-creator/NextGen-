-- Performance hardening for owner-scoped policies and foreign-key lookups.
DROP POLICY IF EXISTS "owners manage their channels" ON public.channels;
CREATE POLICY "owners manage their channels"
  ON public.channels FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

DROP POLICY IF EXISTS "owners manage their content" ON public.content_items;
CREATE POLICY "owners manage their content"
  ON public.content_items FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

DROP POLICY IF EXISTS "owners manage their approval events" ON public.approval_events;
CREATE POLICY "owners manage their approval events"
  ON public.approval_events FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

DROP POLICY IF EXISTS "owners manage their automation settings" ON public.automation_settings;
CREATE POLICY "owners manage their automation settings"
  ON public.automation_settings FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

DROP POLICY IF EXISTS "Owners can view their platform connections" ON public.platform_connections;
DROP POLICY IF EXISTS "Owners can add their platform connections" ON public.platform_connections;
DROP POLICY IF EXISTS "Owners can update their platform connections" ON public.platform_connections;

CREATE POLICY "Owners can view their platform connections"
  ON public.platform_connections FOR SELECT TO authenticated
  USING ((select auth.uid()) = owner_id);
CREATE POLICY "Owners can add their platform connections"
  ON public.platform_connections FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = owner_id);
CREATE POLICY "Owners can update their platform connections"
  ON public.platform_connections FOR UPDATE TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

CREATE INDEX IF NOT EXISTS approval_events_content_owner_idx
  ON public.approval_events(content_id, owner_id);
CREATE INDEX IF NOT EXISTS channel_analytics_channel_owner_idx
  ON public.channel_analytics_daily(channel_id, owner_id);
CREATE INDEX IF NOT EXISTS content_analytics_content_owner_idx
  ON public.content_analytics_daily(content_id, owner_id);
CREATE INDEX IF NOT EXISTS publishing_jobs_channel_owner_idx
  ON public.publishing_jobs(channel_id, owner_id);
CREATE INDEX IF NOT EXISTS publishing_jobs_content_owner_idx
  ON public.publishing_jobs(content_id, owner_id);
CREATE INDEX IF NOT EXISTS activity_logs_actor_user_idx
  ON public.activity_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS content_items_approved_by_idx
  ON public.content_items(approved_by);
