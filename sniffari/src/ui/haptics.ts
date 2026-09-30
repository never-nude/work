import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';

type Kind = 'tap' | 'select' | 'press' | 'success' | 'warning' | 'turn';

/** Taptic feedback on the phone; the vibration API elsewhere; silent if neither exists. */
export function haptic(kind: Kind): void {
  try {
    if (Capacitor.isNativePlatform()) {
      if (kind === 'success') void Haptics.notification({ type: NotificationType.Success });
      else if (kind === 'warning') void Haptics.notification({ type: NotificationType.Warning });
      else if (kind === 'turn') void Haptics.impact({ style: ImpactStyle.Heavy });
      else if (kind === 'select') void Haptics.selectionChanged();
      else void Haptics.impact({ style: kind === 'press' ? ImpactStyle.Medium : ImpactStyle.Light });
      return;
    }
    navigator.vibrate?.(kind === 'tap' ? 8 : kind === 'warning' ? [30, 60, 30] : 20);
  } catch {
    /* haptics are a nicety */
  }
}

/**
 * A light tick on every button, chip and toggle, app-wide — one listener instead of
 * sprinkling calls through every component. Choice controls (chips, segmented) get the
 * crisper "selection" tick; everything else a light impact.
 */
export function installTapHaptics(): void {
  document.addEventListener(
    'click',
    (e) => {
      const el = (e.target as Element | null)?.closest('button, a.btn, [role="radio"]');
      if (!el || (el as HTMLButtonElement).disabled) return;
      haptic(el.matches('.chip, [role="radio"]') ? 'select' : 'tap');
    },
    { capture: true, passive: true },
  );
}
