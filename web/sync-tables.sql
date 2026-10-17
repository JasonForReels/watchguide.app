-- Per-user tables for WatchGuide web (and later iOS) account sync. Run once in the Supabase SQL editor.
-- Every table is locked to its owner: a signed-in user can only see and change their own rows.

create table if not exists public.user_list_items (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_type text not null check (list_type in ('want_to_watch','watched','liked')),
  media_type text not null check (media_type in ('movie','tv')),
  media_id integer not null,
  title text not null, poster_path text, backdrop_path text, year text, release_date text,
  vote_average double precision, overview text,
  added_at timestamptz not null default now(),
  primary key (user_id, list_type, media_type, media_id)
);

create table if not exists public.user_custom_lists (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_id text not null,
  name text not null, description text, icon_name text default 'folder.fill', display_style text default 'row',
  created_at timestamptz default now(), updated_at timestamptz default now(),
  primary key (user_id, list_id)
);

create table if not exists public.user_custom_list_items (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  list_id text not null,
  media_type text not null check (media_type in ('movie','tv')),
  media_id integer not null,
  title text not null, poster_path text, backdrop_path text, year text, release_date text,
  vote_average double precision, overview text,
  sort_order integer not null default 0,
  added_at timestamptz default now(),
  primary key (user_id, list_id, media_type, media_id)
);

create table if not exists public.user_ratings (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  media_type text not null check (media_type in ('movie','tv')),
  media_id integer not null,
  stars smallint not null check (stars between 1 and 5),
  updated_at timestamptz default now(),
  primary key (user_id, media_type, media_id)
);

create table if not exists public.user_episodes (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  show_id integer not null, season integer not null, episode integer not null,
  primary key (user_id, show_id, season, episode)
);

do $$
declare t text;
begin
  foreach t in array array['user_list_items','user_custom_lists','user_custom_list_items','user_ratings','user_episodes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format('create policy "own rows" on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;
