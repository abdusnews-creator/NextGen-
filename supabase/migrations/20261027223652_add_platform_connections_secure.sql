
create table if not exists public.platform_connections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('youtube','facebook','instagram','threads')),
  platform_user_id text,
  display_name text,
  handle text,
  connection_status text not null default 'pending' check (connection_status in ('not_connected','pending','connected','error')),
  token_expires_at timestamptz,
  scopes text[] not null default '{}',
  last_verified_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, platform, platform_user_id)
);
alter table public.platform_connections enable row level security;
drop policy if exists "Owners can view their platform connections" on public.platform_connections;
create policy "Owners can view their platform connections" on public.platform_connections for select to authenticated using (auth.uid() = owner_id);
drop policy if exists "Owners can add their platform connections" on public.platform_connections;
create policy "Owners can add their platform connections" on public.platform_connections for insert to authenticated with check (auth.uid() = owner_id);
drop policy if exists "Owners can update their platform connections" on public.platform_connections;
create policy "Owners can update their platform connections" on public.platform_connections for update to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create index if not exists platform_connections_owner_platform_idx on public.platform_connections(owner_id, platform);

