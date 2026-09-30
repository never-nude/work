import { useState } from 'react';
import { useSocial } from '../../social/store';
import { useStore } from '../../state/store';

/** Sign in, name your dog, build your pack, see who's walking. Only dog names are ever shown. */
export function PackPanel() {
  const s = useSocial();
  const flyTo = useStore((st) => st.flyTo);
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [dogName, setDogName] = useState('');
  const [joinCode, setJoinCode] = useState('');
  const [joined, setJoined] = useState<string | null>(null);

  if (!s.enabled) return null;

  const shareInvite = async () => {
    if (!s.lastInvite) return;
    const text = `Join ${s.dog?.dog_name ?? 'my dog'}'s pack on Sniffari — code ${s.lastInvite}`;
    try {
      if (navigator.share) await navigator.share({ text });
      else await navigator.clipboard.writeText(text);
    } catch {
      /* cancelled */
    }
  };

  return (
    <section className="field pack" aria-label="Pack">
      <span className="field__label">Pack</span>
      {s.error && <p className="hint hint--error">{s.error}</p>}

      {!s.signedIn && !s.codeSent && (
        <>
          <p className="hint">Share walks with friends' dogs. Only dog names are ever shown — never yours.</p>
          <form className="search" onSubmit={(e) => (e.preventDefault(), void s.sendCode(email))}>
            <input className="input" type="email" autoComplete="email" placeholder="Email for a sign-in code" value={email} onChange={(e) => setEmail(e.target.value)} />
            <button className="btn" disabled={s.busy || !email.includes('@')}>Send</button>
          </form>
        </>
      )}

      {!s.signedIn && s.codeSent && (
        <form className="search" onSubmit={(e) => (e.preventDefault(), void s.verify(code))}>
          <input className="input" inputMode="numeric" autoComplete="one-time-code" placeholder="6-digit code from your email" value={code} onChange={(e) => setCode(e.target.value)} />
          <button className="btn" disabled={s.busy || code.trim().length < 6}>Sign in</button>
        </form>
      )}

      {s.signedIn && !s.dog && (
        <form className="search" onSubmit={(e) => (e.preventDefault(), void s.saveDog(dogName))}>
          <input className="input" placeholder="Your dog's name" maxLength={40} value={dogName} onChange={(e) => setDogName(e.target.value)} />
          <button className="btn" disabled={s.busy || !dogName.trim()}>Save</button>
        </form>
      )}

      {s.signedIn && s.dog && (
        <>
          <p className="pack__title">{s.dog.dog_name}'s pack</p>

          {s.packWalks.length > 0 && (
            <ul className="pack__list">
              {s.packWalks.map((w) => (
                <li key={w.id}>
                  <button
                    className="pack__walk"
                    onClick={() => {
                      s.focus(w.id);
                      if (w.last_lat != null && w.last_lon != null) flyTo?.({ lat: w.last_lat, lon: w.last_lon }, 15.5);
                    }}
                  >
                    <span className="pack__live" /> {w.profiles?.dog_name ?? 'A pack dog'} is walking
                    {w.area_label ? <span className="hint"> · {w.area_label}</span> : null}
                  </button>
                </li>
              ))}
            </ul>
          )}

          {s.pack.length > 0 ? (
            <p className="hint">{s.pack.map((d) => d.dog_name).join(' · ')}</p>
          ) : (
            <p className="hint">No pack yet — invite a friend's dog.</p>
          )}

          <div className="chips">
            <button className="chip" disabled={s.busy} onClick={() => void s.invite()}>
              Invite a dog
            </button>
            {s.lastInvite && (
              <button className="chip chip--on" onClick={() => void shareInvite()}>
                Share code {s.lastInvite}
              </button>
            )}
          </div>

          <form
            className="search"
            onSubmit={async (e) => {
              e.preventDefault();
              const name = await s.join(joinCode);
              if (name) {
                setJoined(name);
                setJoinCode('');
              }
            }}
          >
            <input className="input" placeholder="Got a code? e.g. K7QM-2HXP" value={joinCode} onChange={(e) => setJoinCode(e.target.value)} autoCapitalize="characters" />
            <button className="btn" disabled={s.busy || joinCode.trim().length < 8}>Join</button>
          </form>
          {joined && <p className="hint hint--notice">You're now in {joined}'s pack.</p>}

          <button className="btn pack__signout" onClick={() => void s.signOut()}>
            Sign out
          </button>
        </>
      )}
    </section>
  );
}
