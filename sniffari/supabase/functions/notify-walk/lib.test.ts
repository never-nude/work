import { describe, expect, it } from 'vitest';
import { apnsJwt, apnsPayload, importApnsKey, isDeadToken, walkMessage } from './lib';

describe('walk notifications', () => {
  it('names only the dog', () => {
    const m = walkMessage('started', { dogName: 'Ricky', durationMin: 30, lengthM: 2400, areaLabel: 'White Plains' });
    expect(m).toEqual({ title: '🐕 Ricky is walking', body: '30-min walk · White Plains' });
    expect(walkMessage('ended', { dogName: 'Ricky', durationMin: 30, lengthM: null, areaLabel: null }).title).toBe("Ricky's walk ended");
  });
  it('builds an APNs payload that groups a walk’s start and end', () => {
    const p = apnsPayload('started', 'w1', { title: 't', body: 'b' });
    expect(p.aps['thread-id']).toBe('walk-w1');
    expect(p.walkId).toBe('w1');
  });
  it('recognises dead device tokens', () => {
    expect(isDeadToken(410, undefined)).toBe(true);
    expect(isDeadToken(400, 'BadDeviceToken')).toBe(true);
    expect(isDeadToken(429, 'TooManyRequests')).toBe(false);
  });
});

describe('APNs provider token', () => {
  it('is a verifiable ES256 JWT from a .p8 key', async () => {
    const pair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as CryptoKeyPair;
    const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----`;
    const jwt = await apnsJwt(await importApnsKey(pem), 'KEY123', 'TEAM456', 1_700_000_000);
    const [h, c, s] = jwt.split('.');
    const dec = (x: string) => JSON.parse(atob(x.replace(/-/g, '+').replace(/_/g, '/')));
    expect(dec(h!)).toEqual({ alg: 'ES256', kid: 'KEY123' });
    expect(dec(c!)).toEqual({ iss: 'TEAM456', iat: 1_700_000_000 });
    const sig = Uint8Array.from(atob(s!.replace(/-/g, '+').replace(/_/g, '/') + '=='.slice((s!.length * 3) % 4 ? 0 : 2)), (ch) => ch.charCodeAt(0));
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, sig.slice(0, 64), new TextEncoder().encode(`${h}.${c}`));
    expect(ok).toBe(true);
  });
});
