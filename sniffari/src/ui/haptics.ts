import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';

type Kind = 'tap' | 'press' | 'success' | 'warning' | 'turn';

/** Taptic feedback on the phone; the vibration API elsewhere; silent if neither exists. */
export function haptic(kind: Kind): void {
  try {
    if (Capacitor.isNativePlatform()) {
      if (kind === 'success') void Haptics.notification({ type: NotificationType.Success });
      else if (kind === 'warning') void Haptics.notification({ type: NotificationType.Warning });
      else if (kind === 'turn') void Haptics.impact({ style: ImpactStyle.Heavy });
      else void Haptics.impact({ style: kind === 'press' ? ImpactStyle.Medium : ImpactStyle.Light });
      return;
    }
    navigator.vibrate?.(kind === 'tap' ? 8 : kind === 'warning' ? [30, 60, 30] : 20);
  } catch {
    /* haptics are a nicety */
  }
}
