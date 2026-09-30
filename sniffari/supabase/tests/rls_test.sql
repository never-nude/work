-- Scenario: Ricky and Luna are friends; Luna and Mochi are friends; Bruno is a stranger.
-- Run as each dog and check exactly what they can see.
\set ON_ERROR_STOP on
\set QUIET on
insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a'), -- ricky
  ('00000000-0000-0000-0000-00000000000b'), -- luna
  ('00000000-0000-0000-0000-00000000000c'), -- mochi
  ('00000000-0000-0000-0000-00000000000d'); -- bruno

create function pg_temp.as_dog(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, false);
  execute 'set role authenticated';
end $$;
create function pg_temp.expect(label text, ok boolean) returns void language plpgsql as $$
begin
  if not ok then raise exception 'FAIL: %', label; end if;
  raise notice 'ok  %', label;
end $$;

-- Each dog creates its own profile.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a'); insert into profiles (id, dog_name) values (auth.uid(), 'Ricky'); reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b'); insert into profiles (id, dog_name) values (auth.uid(), 'Luna'); reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000c'); insert into profiles (id, dog_name) values (auth.uid(), 'Mochi'); reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000d'); insert into profiles (id, dog_name) values (auth.uid(), 'Bruno'); reset role;

-- Can't create a profile for someone else.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000d');
do $$ begin
  begin
    insert into profiles (id, dog_name) values ('00000000-0000-0000-0000-00000000000a', 'Imposter');
    raise exception 'FAIL: inserted a profile for another user';
  exception when insufficient_privilege or unique_violation then raise notice 'ok  cannot create a profile for someone else';
  end;
end $$;
reset role;

-- Ricky invites Luna; Luna accepts. Luna invites Mochi; Mochi accepts.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
create temp table codes (who text, code text);
grant all on codes to authenticated;
insert into codes select 'ricky', create_invite();
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect('accepting an invite returns the dog name', accept_invite((select code from codes where who = 'ricky')) = 'Ricky');
insert into codes select 'luna', create_invite();
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000c');
select pg_temp.expect('Mochi joins Luna''s pack', accept_invite((select code from codes where who = 'luna')) = 'Luna');
do $$ begin
  begin
    perform accept_invite((select code from codes where who = 'ricky'));
    raise exception 'FAIL: reused an invite';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'ok  an invite works only once';
  end;
end $$;
reset role;

-- Friends can't be forged by inserting directly.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000d');
do $$ begin
  begin
    insert into friendships values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d');
    raise exception 'FAIL: forged a friendship';
  exception when insufficient_privilege then raise notice 'ok  friendships cannot be inserted directly';
  end;
end $$;
select pg_temp.expect('a stranger sees only their own dog', (select array_agg(dog_name order by dog_name) from profiles) = array['Bruno']);
reset role;

-- Ricky starts a friends-only walk.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
insert into walks (user_id, audience, length_m, duration_min, area_label, last_lat, last_lon, last_at)
  values (auth.uid(), 'friends', 2400, 30, 'White Plains', 41.03, -73.76, now());
reset role;

select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect('a friend (Luna) sees Ricky''s friends-only walk', (select count(*) from walks) = 1);
select pg_temp.expect('Luna sees Ricky''s dog name', exists (select 1 from profiles where dog_name = 'Ricky'));
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000c');
select pg_temp.expect('a friend-of-friend (Mochi) does NOT see a friends-only walk', (select count(*) from walks) = 0);
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect('a stranger (Bruno) sees no walks', (select count(*) from walks) = 0);
reset role;

-- Ricky widens the audience to friends-of-friends.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
update walks set audience = 'fof';
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000c');
select pg_temp.expect('Mochi sees a friends-of-friends walk', (select count(*) from walks) = 1);
select pg_temp.expect('Mochi can read Ricky''s dog name for that walk', exists (select 1 from profiles where dog_name = 'Ricky'));
do $$ begin
  update walks set last_lat = 0;
  if exists (select 1 from walks where last_lat = 0) then raise exception 'FAIL: moved someone else''s walk'; end if;
  raise notice 'ok  viewers cannot change someone else''s walk';
end $$;
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000d');
select pg_temp.expect('Bruno still sees nothing', (select count(*) from walks) = 0);
reset role;

-- Ended and expired walks disappear for everyone but the walker.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
update walks set ended_at = now();
select pg_temp.expect('the walker still sees their ended walk', (select count(*) from walks) = 1);
insert into walks (user_id, started_at, expires_at) values (auth.uid(), now() - interval '2 hours', now() - interval '1 minute');
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect('friends no longer see ended or expired walks', (select count(*) from walks) = 0);
reset role;

-- Walks can't be set to last longer than 4 hours.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
do $$ begin
  begin
    insert into walks (user_id, expires_at) values (auth.uid(), now() + interval '1 day');
    raise exception 'FAIL: day-long walk accepted';
  exception when check_violation then raise notice 'ok  walks are capped at 4 hours';
  end;
end $$;
reset role;

-- Unfriending ends visibility.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
insert into walks (user_id, audience) values (auth.uid(), 'friends');
delete from friendships;
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect('after unfriending, Luna sees nothing', (select count(*) from walks) = 0);
reset role;

-- Push tokens are private.
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
insert into device_tokens (token, user_id) values ('luna-token', auth.uid());
reset role;
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000a');
select pg_temp.expect('nobody can read another dog''s push tokens', (select count(*) from device_tokens) = 0);
reset role;

-- There is nowhere to store an owner's name.
select pg_temp.expect('no owner-name column exists', not exists (
  select 1 from information_schema.columns where table_schema = 'public' and column_name ~ '(owner_name|first_name|last_name|full_name|display_name)'));

\echo ALL RLS TESTS PASSED

-- Notification audience (server-side function).
insert into friendships values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');
insert into walks (id, user_id, audience) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'friends');
insert into walks (id, user_id, audience) values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'fof');
select pg_temp.expect('friends-only walk notifies just Luna',
  (select array_agg(x::text) from walk_audience('10000000-0000-0000-0000-000000000001') x) = array['00000000-0000-0000-0000-00000000000b']);
select pg_temp.expect('friends-of-friends walk also notifies Mochi, never Ricky himself or Bruno',
  (select array_agg(x::text order by x) from walk_audience('10000000-0000-0000-0000-000000000002') x)
    = array['00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c']);
select pg_temp.as_dog('00000000-0000-0000-0000-00000000000b');
do $$ begin
  begin
    perform walk_audience('10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: app users can call walk_audience';
  exception when insufficient_privilege then raise notice 'ok  the audience list is server-only';
  end;
end $$;
reset role;

\echo ALL AUDIENCE TESTS PASSED
