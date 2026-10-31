create extension if not exists pgcrypto;

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('youtube','facebook','instagram','threads')),
  display_name text not null,
  handle text,
  profile_url text,
  connection_status text not null default 'not_connected' check (connection_status in ('not_connected','pending','connected','error')),
  is_paused boolean not null default false,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.content_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid references public.channels(id) on delete set null,
  platform text not null check (platform in ('youtube','facebook','instagram','threads')),
  title text,
  caption text not null default '',
  media_url text,
  hashtags text[] not null default '{}',
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','scheduled','published','rejected','failed')),
  scheduled_for timestamptz,
  published_at timestamptz,
  safety_checks jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint content_channel_owner_match foreign key (channel_id) references public.channels(id) on delete set null
);

create table if not exists public.approval_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  content_id uuid not null references public.content_items(id) on delete cascade,
  action text not null check (action in ('submitted','approved','rejected','returned_for_edit')),
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.automation_settings (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  approval_mode text not null default 'manual' check (approval_mode in ('manual','auto')),
  auto_approval_enabled boolean not null default false,
  background_mode_enabled boolean not null default false,
  timezone text not null default 'Asia/Kolkata',
  daily_idea_times time[] not null default array['08:00'::time,'14:00'::time,'18:00'::time],
  updated_at timestamptz not null default now(),
  constraint auto_mode_consistency check (approval_mode <> 'auto' or auto_approval_enabled = true)
);

create index if not exists channels_owner_idx on public.channels(owner_id);
create index if not exists content_owner_status_idx on public.content_items(owner_id,status);
create index if not exists content_schedule_idx on public.content_items(scheduled_for) where status = 'scheduled';
create index if not exists approval_events_content_idx on public.approval_events(content_id,created_at desc);

alter table public.channels enable row level security;
alter table public.content_items enable row level security;
alter table public.approval_events enable row level security;
alter table public.automation_settings enable row level security;

drop policy if exists "owners manage their channels" on public.channels;
create policy "owners manage their channels" on public.channels
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "owners manage their content" on public.content_items;
create policy "owners manage their content" on public.content_items
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "owners manage their approval events" on public.approval_events;
create policy "owners manage their approval events" on public.approval_events
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "owners manage their automation settings" on public.automation_settings;
create policy "owners manage their automation settings" on public.automation_settings
  for all to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists channels_set_updated_at on public.channels;
create trigger channels_set_updated_at before update on public.channels
for each row execute function public.set_updated_at();

drop trigger if exists content_items_set_updated_at on public.content_items;
create trigger content_items_set_updated_at before update on public.content_items
for each row execute function public.set_updated_at();

drop trigger if exists automation_settings_set_updated_at on public.automation_settings;
create trigger automation_settings_set_updated_at before update on public.automation_settings
for each row execute function public.set_updated_at();
