
-- NextGen schema expansion: additive only; preserve existing records and tables.
ALTER TABLE public.content_items
  ADD COLUMN IF NOT EXISTS content_type text NOT NULL DEFAULT 'reel',
  ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS thumbnail_url text,
  ADD COLUMN IF NOT EXISTS thumbnail_prompt text,
  ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS keywords text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS seo_score numeric(5,2),
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS external_post_id text,
  ADD COLUMN IF NOT EXISTS last_publish_error text,
  ADD COLUMN IF NOT EXISTS publish_attempts integer NOT NULL DEFAULT 0;

ALTER TABLE public.content_items
  ADD CONSTRAINT content_items_content_type_check
  CHECK (content_type IN ('reel','short_video','long_form_video','photo_post','carousel_photo_post','story','text_post'))
  NOT VALID;
ALTER TABLE public.content_items VALIDATE CONSTRAINT content_items_content_type_check;
ALTER TABLE public.content_items
  ADD CONSTRAINT content_items_seo_score_check
  CHECK (seo_score IS NULL OR (seo_score >= 0 AND seo_score <= 100))
  NOT VALID;
ALTER TABLE public.content_items VALIDATE CONSTRAINT content_items_seo_score_check;
ALTER TABLE public.content_items
  ADD CONSTRAINT content_items_publish_attempts_check
  CHECK (publish_attempts >= 0)
  NOT VALID;
ALTER TABLE public.content_items VALIDATE CONSTRAINT content_items_publish_attempts_check;

ALTER TABLE public.channels
  ADD COLUMN IF NOT EXISTS external_channel_id text,
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_sync_error text;

ALTER TABLE public.content_items
  ADD CONSTRAINT content_items_id_owner_id_unique UNIQUE (id, owner_id);

ALTER TABLE public.approval_events
  ADD CONSTRAINT approval_events_content_owner_match
  FOREIGN KEY (content_id, owner_id)
  REFERENCES public.content_items(id, owner_id)
  ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS public.publishing_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id uuid NOT NULL,
  channel_id uuid NOT NULL,
  scheduled_for timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','processing','published','failed','cancelled')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts integer NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
  next_attempt_at timestamptz,
  external_post_id text,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT publishing_jobs_content_owner_fk
    FOREIGN KEY (content_id, owner_id)
    REFERENCES public.content_items(id, owner_id) ON DELETE CASCADE,
  CONSTRAINT publishing_jobs_channel_owner_fk
    FOREIGN KEY (channel_id, owner_id)
    REFERENCES public.channels(id, owner_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.channel_analytics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_id uuid NOT NULL,
  metric_date date NOT NULL,
  views bigint NOT NULL DEFAULT 0 CHECK (views >= 0),
  reach bigint NOT NULL DEFAULT 0 CHECK (reach >= 0),
  followers bigint NOT NULL DEFAULT 0 CHECK (followers >= 0),
  followers_gained bigint NOT NULL DEFAULT 0,
  likes bigint NOT NULL DEFAULT 0 CHECK (likes >= 0),
  comments bigint NOT NULL DEFAULT 0 CHECK (comments >= 0),
  shares bigint NOT NULL DEFAULT 0 CHECK (shares >= 0),
  watch_time_seconds bigint NOT NULL DEFAULT 0 CHECK (watch_time_seconds >= 0),
  engagement_rate numeric(7,4),
  source text NOT NULL DEFAULT 'platform_api',
  raw_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT channel_analytics_channel_owner_fk
    FOREIGN KEY (channel_id, owner_id)
    REFERENCES public.channels(id, owner_id) ON DELETE CASCADE,
  CONSTRAINT channel_analytics_daily_unique UNIQUE (channel_id, metric_date),
  CONSTRAINT channel_analytics_engagement_check
    CHECK (engagement_rate IS NULL OR (engagement_rate >= 0 AND engagement_rate <= 100))
);

CREATE TABLE IF NOT EXISTS public.content_analytics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id uuid NOT NULL,
  metric_date date NOT NULL,
  views bigint NOT NULL DEFAULT 0 CHECK (views >= 0),
  reach bigint NOT NULL DEFAULT 0 CHECK (reach >= 0),
  likes bigint NOT NULL DEFAULT 0 CHECK (likes >= 0),
  comments bigint NOT NULL DEFAULT 0 CHECK (comments >= 0),
  shares bigint NOT NULL DEFAULT 0 CHECK (shares >= 0),
  saves bigint NOT NULL DEFAULT 0 CHECK (saves >= 0),
  watch_time_seconds bigint NOT NULL DEFAULT 0 CHECK (watch_time_seconds >= 0),
  average_view_duration_seconds numeric(12,2),
  engagement_rate numeric(7,4),
  source text NOT NULL DEFAULT 'platform_api',
  raw_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT content_analytics_content_owner_fk
    FOREIGN KEY (content_id, owner_id)
    REFERENCES public.content_items(id, owner_id) ON DELETE CASCADE,
  CONSTRAINT content_analytics_daily_unique UNIQUE (content_id, metric_date),
  CONSTRAINT content_analytics_engagement_check
    CHECK (engagement_rate IS NULL OR (engagement_rate >= 0 AND engagement_rate <= 100))
);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  owner_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  in_app_enabled boolean NOT NULL DEFAULT true,
  email_enabled boolean NOT NULL DEFAULT true,
  push_enabled boolean NOT NULL DEFAULT false,
  approval_updates boolean NOT NULL DEFAULT true,
  publishing_updates boolean NOT NULL DEFAULT true,
  connection_alerts boolean NOT NULL DEFAULT true,
  weekly_analytics boolean NOT NULL DEFAULT true,
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS publishing_jobs_owner_status_time_idx
  ON public.publishing_jobs(owner_id, status, scheduled_for);
CREATE INDEX IF NOT EXISTS publishing_jobs_retry_idx
  ON public.publishing_jobs(status, next_attempt_at)
  WHERE status IN ('queued','failed');
CREATE INDEX IF NOT EXISTS channel_analytics_owner_date_idx
  ON public.channel_analytics_daily(owner_id, metric_date DESC);
CREATE INDEX IF NOT EXISTS content_analytics_owner_date_idx
  ON public.content_analytics_daily(owner_id, metric_date DESC);
CREATE INDEX IF NOT EXISTS activity_logs_owner_created_idx
  ON public.activity_logs(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS approval_events_owner_idx
  ON public.approval_events(owner_id);
CREATE INDEX IF NOT EXISTS content_items_channel_owner_idx
  ON public.content_items(channel_id, owner_id);

ALTER TABLE public.publishing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_analytics_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_analytics_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owners manage their publishing jobs"
  ON public.publishing_jobs FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);
CREATE POLICY "owners manage their channel analytics"
  ON public.channel_analytics_daily FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);
CREATE POLICY "owners manage their content analytics"
  ON public.content_analytics_daily FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);
CREATE POLICY "owners manage their notification preferences"
  ON public.notification_preferences FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);
CREATE POLICY "owners manage their activity logs"
  ON public.activity_logs FOR ALL TO authenticated
  USING ((select auth.uid()) = owner_id)
  WITH CHECK ((select auth.uid()) = owner_id);

REVOKE ALL ON public.publishing_jobs, public.channel_analytics_daily,
  public.content_analytics_daily, public.notification_preferences,
  public.activity_logs FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.publishing_jobs,
  public.channel_analytics_daily, public.content_analytics_daily,
  public.notification_preferences, public.activity_logs TO authenticated;
GRANT ALL ON public.publishing_jobs, public.channel_analytics_daily,
  public.content_analytics_daily, public.notification_preferences,
  public.activity_logs TO service_role;

