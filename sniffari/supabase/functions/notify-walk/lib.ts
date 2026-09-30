// Pure logic for notify-walk (no Deno APIs) so it can be unit-tested with Vitest.

export type WalkEvent = 'started' | 'ended';

export interface WalkSummary {
  dogName: string;
  durationMin: number | null;
  lengthM: number | null;
  areaLabel: string | null;
}

/** Notification text. Only the dog's name ever appears — never an owner's. */
export function walkMessage(event: WalkEvent, w: WalkSummary): { title: string; body: string } {
  const dog = w.dogName.trim() || 'A pack dog';
  if (event === 'ended') return { title: `${dog}'s walk ended`, body: 'Thanks for walking together.' };
  const parts: string[] = [];
  if (w.durationMin) parts.push(`${w.durationMin}-min walk`);
  else if (w.lengthM) parts.push(`${(w.lengthM / 1609.344).toFixed(1)} mi walk`);
  if (w.areaLabel) parts.push(w.areaLabel);
  return { title: `🐕 ${dog} is walking`, body: parts.length ? parts.join(' · ') : 'Tap to see where' };
}

export function apnsPayload(event: WalkEvent, walkId: string, msg: { title: string; body: string }) {
  return {
    aps: {
      alert: msg,
      sound: 'default',
      'thread-id': `walk-${walkId}`,
      // A finished walk quietly replaces its "is walking" alert.
      ...(event === 'ended' ? { 'interruption-level': 'passive' } : {}),
    },
    walkId,
    event,
  };
}

const b64url = (bytes: Uint8Array | string) => {
  const bin = typeof bytes === 'string' ? bytes : String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

/** Import an APNs .p8 (PKCS#8 PEM) signing key. */
export async function importApnsKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

/** APNs provider token (ES256 JWT). Apple accepts one for up to an hour. */
export async function apnsJwt(key: CryptoKey, keyId: string, teamId: string, nowS = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: nowS }));
  const input = `${header}.${claims}`;
  // WebCrypto returns the raw r||s signature JWS expects.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(input)));
  return `${input}.${b64url(sig)}`;
}

/** Tokens Apple says are dead — delete them so we stop sending. */
export function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered' || reason === 'DeviceTokenNotForTopic';
}
