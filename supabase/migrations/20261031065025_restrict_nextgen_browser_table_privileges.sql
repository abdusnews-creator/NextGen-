-- Remove elevated table-level privileges that bypass row-level policies.
-- Browser users keep only the CRUD operations required by the app.
REVOKE ALL ON TABLE public.channels,
  public.channel_analytics_daily, public.content_analytics_daily,
  public.notification_preferences, public.activity_logs
  FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.channels TO authenticated;
GRANT SELECT ON public.channel_analytics_daily,
  public.content_analytics_daily, public.activity_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
