-- NextGen initial database schema for Supabase/PostgreSQL.
-- Review and run in the project's own Supabase SQL editor only after creating a project.
-- No social platform access tokens belong in these tables.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('youtube','facebook','instagram','threads')),
  display_name text not null,
  handle text,
  connection_status text not null default 'not_connected'
    check (connection_status in ('not_connected','pending','connected','error','paused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.content_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid references public.channels(id) on delete set null,
  title text not null,
  caption text not null default '',
  status text not null default 'pending_approval'
    check (status in ('draft','pending_approval','approved','rejected','revised','scheduled','published')),
  approval_mode text not null default 'manual'
    check (approval_mode in ('manual','auto')),
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.draft_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  draft_id uuid not null references public.content_drafts(id) on delete cascade,
  spelling_checked boolean not null default false,
  facts_checked boolean not null default false,
  copyright_checked boolean not null default false,
  duplicate_checked boolean not null default false,
  platform_safety_checked boolean not null default false,
  notes text not null default '',
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (draft_id)
);

alter table public.profiles enable row level security;
alter table public.channels enable row level security;
alter table public.content_drafts enable row level security;
alter table public.draft_reviews enable row level security;

drop policy if exists "Users manage own profile" on public.profiles;
create policy "Users manage own profile" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "Users manage own channels" on public.channels;
create policy "Users manage own channels" on public.channels
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users manage own drafts" on public.content_drafts;
create policy "Users manage own drafts" on public.content_drafts
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Users manage own draft reviews" on public.draft_reviews;
create policy "Users manage own draft reviews" on public.draft_reviews
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Approval safeguard: a draft can only be marked approved when its matching
-- review row has all five checks complete. This does not publish anything.
create or replace function public.enforce_review_before_approval()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from new.status then
    if not exists (
      select 1 from public.draft_reviews r
      where r.draft_id = new.id
        and r.user_id = new.user_id
        and r.spelling_checked
        and r.facts_checked
        and r.copyright_checked
        and r.duplicate_checked
        and r.platform_safety_checked
    ) then
      raise exception 'Approval requires all five review checks to be complete';
    end if;
    new.approved_at := now();
    new.approved_by := auth.uid();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists content_drafts_approval_guard on public.content_drafts;
create trigger content_drafts_approval_guard
before update on public.content_drafts
for each row execute function public.enforce_review_before_approval();

-- Important: real authentication, account provisioning, secret management,
-- platform OAuth and background workers still require backend configuration.
