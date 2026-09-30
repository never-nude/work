import type { LatLon, LngLat } from '../types';
import { supabase } from './client';

export type Audience = 'friends' | 'fof';

export interface DogProfile {
  id: string;
  dog_name: string;
  dog_photo_url: string | null;
}

export interface LiveWalk {
  id: string;
  user_id: string;
  audience: Audience;
  started_at: string;
  expires_at: string;
  ended_at: string | null;
  length_m: number | null;
  duration_min: number | null;
  area_label: string | null;
  route: LngLat[] | null;
  last_lat: number | null;
  last_lon: number | null;
  last_at: string | null;
  profiles?: { dog_name: string } | null;
}

const db = () => {
  if (!supabase) throw new Error('Pack features are not set up (missing Supabase keys).');
  return supabase;
};

const check = <T>(r: { data: T; error: { message: string } | null }): T => {
  if (r.error) throw new Error(r.error.message);
  return r.data;
};

// ------------------------------------------------------------- sign-in (email code, no names)

export async function sendCode(email: string): Promise<void> {
  check(await db().auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: true } }));
}

export async function verifyCode(email: string, code: string): Promise<void> {
  check(await db().auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'email' }));
}

export async function signOut(): Promise<void> {
  await db().auth.signOut();
}

export async function currentUserId(): Promise<string | null> {
  return (await db().auth.getUser()).data.user?.id ?? null;
}

// ------------------------------------------------------------- dog profile

export async function getMyDog(): Promise<DogProfile | null> {
  const uid = await currentUserId();
  if (!uid) return null;
  return check(await db().from('profiles').select('id, dog_name, dog_photo_url').eq('id', uid).maybeSingle());
}

export async function saveDogName(name: string): Promise<DogProfile> {
  const uid = await currentUserId();
  if (!uid) throw new Error('Not signed in');
  return check(
    await db().from('profiles').upsert({ id: uid, dog_name: name.trim() }).select('id, dog_name, dog_photo_url').single(),
  ) as DogProfile;
}

// ------------------------------------------------------------- pack

export async function createInvite(): Promise<string> {
  return check(await db().rpc('create_invite')) as string;
}

/** Returns the new friend's dog name. */
export async function acceptInvite(code: string): Promise<string> {
  return check(await db().rpc('accept_invite', { invite_code: code })) as string;
}

export async function listPack(): Promise<DogProfile[]> {
  const uid = await currentUserId();
  if (!uid) return [];
  const rows = check(await db().from('friendships').select('user_a, user_b')) as { user_a: string; user_b: string }[];
  const ids = rows.map((r) => (r.user_a === uid ? r.user_b : r.user_a));
  if (!ids.length) return [];
  return (check(await db().from('profiles').select('id, dog_name, dog_photo_url').in('id', ids).order('dog_name')) ?? []) as DogProfile[];
}

export async function leavePack(friendId: string): Promise<void> {
  const uid = await currentUserId();
  if (!uid) return;
  const [a, b] = uid < friendId ? [uid, friendId] : [friendId, uid];
  check(await db().from('friendships').delete().eq('user_a', a).eq('user_b', b));
}

// ------------------------------------------------------------- live walks

export async function startLiveWalk(w: {
  audience: Audience;
  minutes: number;
  lengthM: number;
  durationMin: number;
  areaLabel: string | null;
  route: LngLat[];
}): Promise<LiveWalk> {
  const uid = await currentUserId();
  if (!uid) throw new Error('Not signed in');
  const expires = new Date(Date.now() + Math.min(w.minutes, 240) * 60_000).toISOString();
  const walk = check(
    await db()
      .from('walks')
      .insert({
        user_id: uid,
        audience: w.audience,
        expires_at: expires,
        length_m: Math.round(w.lengthM),
        duration_min: Math.round(w.durationMin),
        area_label: w.areaLabel,
        route: w.route,
      })
      .select('*')
      .single(),
  ) as LiveWalk;
  void db().functions.invoke('notify-walk', { body: { walkId: walk.id, event: 'started' } });
  return walk;
}

export async function publishPosition(walkId: string, p: LatLon): Promise<void> {
  check(await db().from('walks').update({ last_lat: p.lat, last_lon: p.lon, last_at: new Date().toISOString() }).eq('id', walkId));
}

export async function endLiveWalk(walkId: string): Promise<void> {
  check(await db().from('walks').update({ ended_at: new Date().toISOString(), last_lat: null, last_lon: null }).eq('id', walkId));
  void db().functions.invoke('notify-walk', { body: { walkId, event: 'ended' } });
}

/** Friends' live walks right now (RLS already limits this to what you may see). */
export async function listPackWalks(): Promise<LiveWalk[]> {
  const uid = await currentUserId();
  const rows = check(
    await db().from('walks').select('*, profiles(dog_name)').is('ended_at', null).gt('expires_at', new Date().toISOString()),
  ) as LiveWalk[];
  return rows.filter((w) => w.user_id !== uid);
}

/** Calls `onChange` whenever a visible walk starts, moves or ends. Returns an unsubscribe function. */
export function watchPackWalks(onChange: () => void): () => void {
  const ch = db()
    .channel('pack-walks')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'walks' }, () => onChange())
    .subscribe();
  return () => void db().removeChannel(ch);
}

export async function saveDeviceToken(token: string, platform: 'ios' | 'android' | 'web'): Promise<void> {
  const uid = await currentUserId();
  if (!uid) return;
  check(await db().from('device_tokens').upsert({ token, user_id: uid, platform, updated_at: new Date().toISOString() }));
}
