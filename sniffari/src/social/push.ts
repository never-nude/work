import { Capacitor } from '@capacitor/core';
import { PushNotifications } from '@capacitor/push-notifications';
import { saveDeviceToken } from './api';

/** Ask for notification permission (native only) and store this phone's push token for the pack. */
export async function registerForPush(onOpenWalk: (walkId: string) => void): Promise<void> {
  if (!Capacitor.isNativePlatform()) return;
  let perm = await PushNotifications.checkPermissions();
  if (perm.receive === 'prompt') perm = await PushNotifications.requestPermissions();
  if (perm.receive !== 'granted') return;
  await PushNotifications.removeAllListeners();
  await PushNotifications.addListener('registration', (t) => void saveDeviceToken(t.value, Capacitor.getPlatform() === 'android' ? 'android' : 'ios'));
  await PushNotifications.addListener('pushNotificationActionPerformed', (a) => {
    const walkId = (a.notification.data as { walkId?: string } | undefined)?.walkId;
    if (walkId) onOpenWalk(walkId);
  });
  await PushNotifications.register();
}
