import { create } from 'zustand';
import type { LatLon, Route } from '../types';
import { reverseArea } from '../data/geocode';
import * as api from './api';
import { socialEnabled, supabase } from './client';
import { makePositionGate, mayPublishPosition, publicRoute } from './privacy';
import { registerForPush } from './push';

export type ShareMode = 'off' | 'friends' | 'fof';

interface SocialState {
  enabled: boolean;
  signedIn: boolean;
  email: string;
  codeSent: boolean;
  busy: boolean;
  error: string | null;
  dog: api.DogProfile | null;
  pack: api.DogProfile[];
  packWalks: api.LiveWalk[];
  lastInvite: string | null;
  /** Per-walk choice made before pressing Start walk. */
  shareMode: ShareMode;
  myWalk: api.LiveWalk | null;
  focusWalkId: string | null;

  init(): Promise<void>;
  sendCode(email: string): Promise<void>;
  verify(code: string): Promise<void>;
  signOut(): Promise<void>;
  saveDog(name: string): Promise<void>;
  invite(): Promise<void>;
  join(code: string): Promise<string | null>;
  refresh(): Promise<void>;
  setShareMode(m: ShareMode): void;
  goLive(route: Route): Promise<void>;
  onMyPosition(p: LatLon): void;
  endLive(): Promise<void>;
  focus(walkId: string | null): void;
}

let unwatch: (() => void) | null = null;
let gate = makePositionGate();
let liveCoords: Route['coords'] = [];

export const useSocial = create<SocialState>((set, get) => {
  const run = async <T>(fn: () => Promise<T>): Promise<T | null> => {
    set({ busy: true, error: null });
    try {
      return await fn();
    } catch (e) {
      set({ error: e instanceof Error ? e.message : String(e) });
      return null;
    } finally {
      set({ busy: false });
    }
  };

  const afterSignIn = async () => {
    const dog = await api.getMyDog();
    set({ signedIn: true, dog });
    await get().refresh();
    unwatch?.();
    unwatch = api.watchPackWalks(() => void api.listPackWalks().then((packWalks) => set({ packWalks })));
    void registerForPush((walkId) => get().focus(walkId));
  };

  return {
    enabled: socialEnabled,
    signedIn: false,
    email: '',
    codeSent: false,
    busy: false,
    error: null,
    dog: null,
    pack: [],
    packWalks: [],
    lastInvite: null,
    shareMode: 'off',
    myWalk: null,
    focusWalkId: null,

    init: async () => {
      if (!supabase) return;
      const { data } = await supabase.auth.getSession();
      if (data.session) await run(afterSignIn);
      supabase.auth.onAuthStateChange((_e, session) => {
        if (!session) {
          unwatch?.();
          set({ signedIn: false, dog: null, pack: [], packWalks: [], myWalk: null });
        }
      });
    },
    sendCode: async (email) => {
      set({ email });
      if ((await run(() => api.sendCode(email))) !== null) set({ codeSent: true });
    },
    verify: async (code) => {
      await run(async () => {
        await api.verifyCode(get().email, code);
        await afterSignIn();
      });
    },
    signOut: async () => {
      await run(api.signOut);
      set({ codeSent: false });
    },
    saveDog: async (name) => {
      const dog = await run(() => api.saveDogName(name));
      if (dog) set({ dog });
    },
    invite: async () => {
      const code = await run(api.createInvite);
      if (code) set({ lastInvite: code });
    },
    join: async (code) => {
      const name = await run(() => api.acceptInvite(code));
      if (name) await get().refresh();
      return name;
    },
    refresh: async () => {
      const [pack, packWalks] = await Promise.all([api.listPack(), api.listPackWalks()]);
      set({ pack, packWalks });
    },
    setShareMode: (shareMode) => set({ shareMode }),

    goLive: async (route) => {
      const { shareMode, signedIn, dog } = get();
      if (shareMode === 'off' || !signedIn || !dog) return;
      liveCoords = route.coords;
      gate = makePositionGate();
      const mid = route.coords[route.coords.length >> 1]!;
      const areaLabel = await reverseArea({ lat: mid[1], lon: mid[0] });
      const walk = await run(() =>
        api.startLiveWalk({
          audience: shareMode,
          minutes: Math.ceil(route.durationMin * 1.5) + 15,
          lengthM: route.lengthM,
          durationMin: route.durationMin,
          areaLabel,
          route: publicRoute(route.coords),
        }),
      );
      if (walk) set({ myWalk: walk });
    },
    onMyPosition: (p) => {
      const w = get().myWalk;
      if (!w || !mayPublishPosition(p, liveCoords) || !gate(p)) return;
      void api.publishPosition(w.id, p).catch(() => {});
    },
    endLive: async () => {
      const w = get().myWalk;
      set({ myWalk: null });
      if (w) await run(() => api.endLiveWalk(w.id));
    },
    focus: (focusWalkId) => set({ focusWalkId }),
  };
});
