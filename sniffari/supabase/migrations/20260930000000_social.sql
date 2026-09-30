-- Sniffari social layer: dogs, packs (friends), live walks, push tokens.
--
-- Privacy rules baked into the schema:
--   * Dogs are the identity. There is no column for an owner's name, and none is ever shown.
--   * Live walks are visible only to the walker's friends, or friends-of-friends when the
--     walker chooses that audience for that walk — never to strangers.
--   * Every walk expires; ended or expired walks are invisible to everyone but the walker.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- dogs (profiles)

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  dog_name text not null check (char_length(btrim(dog_name)) between 1 and 40),
  dog_photo_url text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- pack (friendships)

-- One row per pair, stored with user_a < user_b so a pair can't be duplicated.
create table public.friendships (
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_b on public.friendships (user_b);

create table public.invites (
  code text primary key,
  owner uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid references public.profiles (id) on delete set null,
  used_at timestamptz
);

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships where user_a = least(a, b) and user_b = greatest(a, b)
  );
$$;

create or replace function public.friend_ids(u uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select user_b from friendships where user_a = u
  union
  select user_a from friendships where user_b = u;
$$;

-- True when a and b are not friends but share at least one friend.
create or replace function public.friends_of_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and exists (
    select 1 from friend_ids(a) fa join friend_ids(b) fb on fa = fb
  );
$$;

-- ---------------------------------------------------------------- live walks

create table public.walks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  audience text not null default 'friends' check (audience in ('friends', 'fof')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 minutes',
  ended_at timestamptz,
  length_m integer check (length_m >= 0),
  duration_min integer check (duration_min >= 0),
  -- Coarse place only (town / neighbourhood), never a street address.
  area_label text check (char_length(area_label) <= 80),
  -- Route with the first and last ~150 m removed on the device (keeps the front door private).
  route jsonb,
  last_lat double precision,
  last_lon double precision,
  last_at timestamptz,
  check (expires_at <= started_at + interval '4 hours')
);
create index walks_active on public.walks (user_id) where ended_at is null;

create or replace function public.walk_is_live(w public.walks) returns boolean
language sql stable as $$
  select w.ended_at is null and w.expires_at > now();
$$;

create or replace function public.can_see_walk(viewer uuid, w public.walks) returns boolean
language sql stable security definer set search_path = public as $$
  select viewer = w.user_id
      or (walk_is_live(w) and (
            are_friends(viewer, w.user_id)
            or (w.audience = 'fof' and friends_of_friends(viewer, w.user_id))
         ));
$$;

-- ---------------------------------------------------------------- push tokens

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'ios' check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- invites

create or replace function public.create_invite() returns text
language plpgsql security definer set search_path = public as $$
declare
  c text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  -- 8 unambiguous characters, e.g. "K7QM-2HXP"
  c := upper(substr(translate(encode(gen_random_bytes(12), 'base64'), '+/=01OIl', ''), 1, 8));
  c := substr(c, 1, 4) || '-' || substr(c, 5, 4);
  insert into invites (code, owner) values (c, auth.uid());
  return c;
end;
$$;

-- Accepting an invite makes the two dogs friends. Returns the new friend's dog name.
create or replace function public.accept_invite(invite_code text) returns text
language plpgsql security definer set search_path = public as $$
declare
  inv invites;
  me uuid := auth.uid();
  dog text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into inv from invites where code = upper(btrim(invite_code)) for update;
  if not found then raise exception 'invite not found'; end if;
  if inv.used_by is not null then raise exception 'invite already used'; end if;
  if inv.expires_at < now() then raise exception 'invite expired'; end if;
  if inv.owner = me then raise exception 'that is your own invite'; end if;
  insert into friendships (user_a, user_b) values (least(me, inv.owner), greatest(me, inv.owner))
    on conflict do nothing;
  update invites set used_by = me, used_at = now() where code = inv.code;
  select dog_name into dog from profiles where id = inv.owner;
  return dog;
end;
$$;

-- ---------------------------------------------------------------- row level security

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.invites enable row level security;
alter table public.walks enable row level security;
alter table public.device_tokens enable row level security;

-- Dog names are visible to yourself, your pack, and friends-of-friends (so a shared walk can say whose it is).
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or are_friends(auth.uid(), id) or friends_of_friends(auth.uid(), id));
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Friendships: see and remove your own; creating one only happens through accept_invite().
create policy friendships_read on public.friendships for select to authenticated
  using (auth.uid() in (user_a, user_b));
create policy friendships_delete on public.friendships for delete to authenticated
  using (auth.uid() in (user_a, user_b));

create policy invites_own on public.invites for select to authenticated using (owner = auth.uid());

create policy walks_read on public.walks for select to authenticated using (can_see_walk(auth.uid(), walks));
create policy walks_insert on public.walks for insert to authenticated with check (user_id = auth.uid());
create policy walks_update on public.walks for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy walks_delete on public.walks for delete to authenticated using (user_id = auth.uid());

create policy tokens_own on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update on public.profiles to authenticated;
grant select, delete on public.friendships to authenticated;
grant select on public.invites to authenticated;
grant select, insert, update, delete on public.walks to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant execute on function public.create_invite(), public.accept_invite(text) to authenticated;
revoke all on all tables in schema public from anon;

-- Live updates for friends' walks (Realtime applies the same RLS).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.walks;
  end if;
end $$;

-- ---------------------------------------------------------------- notification audience

-- Who should hear about a walk: friends, plus friends-of-friends when the walker chose that.
-- Server-only (the notify-walk function uses the service role); not callable from the app.
create or replace function public.walk_audience(walk_id uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  with w as (select * from walks where id = walk_id),
  f as (select friend_ids(w.user_id) as id from w),
  fof as (
    select distinct friend_ids(f.id) as id from f, w where w.audience = 'fof'
  )
  select id from f
  union
  select fof.id from fof, w where fof.id <> w.user_id;
$$;
revoke execute on function public.walk_audience(uuid) from public, anon, authenticated;
