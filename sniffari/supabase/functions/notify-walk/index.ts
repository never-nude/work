// Supabase Edge Function: push "🐕 Ricky is walking" / "Ricky's walk ended" to the walker's audience.
//
// Called by the app right after it starts or ends a live walk:
//   supabase.functions.invoke('notify-walk', { body: { walkId, event: 'started' | 'ended' } })
//
// Secrets (supabase secrets set …): APNS_KEY (contents of the .p8), APNS_KEY_ID, APNS_TEAM_ID,
// APNS_BUNDLE_ID (e.g. work.kushman.sniffari). Production and sandbox (Xcode-installed) tokens both work.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { APNS_HOSTS, apnsJwt, apnsPayload, importApnsKey, isDeadToken, shouldTryNextHost, walkMessage, type WalkEvent } from './lib.ts';

const env = (k: string) => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`missing secret ${k}`);
  return v;
};

Deno.serve(async (req) => {
  try {
    const { walkId, event } = (await req.json()) as { walkId?: string; event?: WalkEvent };
    if (!walkId || (event !== 'started' && event !== 'ended')) return json({ error: 'walkId and event required' }, 400);

    // Who is calling? Must be the walker.
    const url = env('SUPABASE_URL');
    const asCaller = createClient(url, env('SUPABASE_ANON_KEY'), {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: me } = await asCaller.auth.getUser();
    if (!me.user) return json({ error: 'not signed in' }, 401);

    const admin = createClient(url, env('SUPABASE_SERVICE_ROLE_KEY'));
    const { data: walk } = await admin
      .from('walks')
      .select('id, user_id, duration_min, length_m, area_label, profiles!inner(dog_name)')
      .eq('id', walkId)
      .single();
    if (!walk || walk.user_id !== me.user.id) return json({ error: 'not your walk' }, 403);

    const { data: audience } = await admin.rpc('walk_audience', { walk_id: walkId });
    const ids = ((audience ?? []) as string[]).filter(Boolean);
    if (!ids.length) return json({ sent: 0 });
    const { data: tokens } = await admin.from('device_tokens').select('token').in('user_id', ids).eq('platform', 'ios');
    if (!tokens?.length) return json({ sent: 0 });

    const dogName = (walk as unknown as { profiles: { dog_name: string } }).profiles.dog_name;
    const msg = walkMessage(event, { dogName, durationMin: walk.duration_min, lengthM: walk.length_m, areaLabel: walk.area_label });
    const payload = JSON.stringify(apnsPayload(event, walkId, msg));
    const jwt = await apnsJwt(await importApnsKey(env('APNS_KEY')), env('APNS_KEY_ID'), env('APNS_TEAM_ID'));

    let sent = 0;
    const dead: string[] = [];
    await Promise.all(
      tokens.map(async ({ token }) => {
        let status = 0;
        let reason: string | undefined;
        for (const host of APNS_HOSTS) {
          const r = await fetch(`https://${host}/3/device/${token}`, {
            method: 'POST',
            headers: {
              authorization: `bearer ${jwt}`,
              'apns-topic': env('APNS_BUNDLE_ID'),
              'apns-push-type': 'alert',
              'apns-priority': event === 'started' ? '10' : '5',
              'apns-collapse-id': `walk-${walkId}`,
            },
            body: payload,
          });
          status = r.status;
          reason = r.ok ? undefined : ((await r.json().catch(() => ({}))) as { reason?: string }).reason;
          if (r.ok || !shouldTryNextHost(status, reason)) break;
        }
        if (status === 200) sent++;
        else if (isDeadToken(status, reason)) dead.push(token);
        else console.warn('apns', status, reason);
      }),
    );
    if (dead.length) await admin.from('device_tokens').delete().in('token', dead);
    return json({ sent, removed: dead.length });
  } catch (e) {
    console.error(e);
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
