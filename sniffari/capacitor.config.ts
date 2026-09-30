import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  // Bundle ID — must be unique in App Store Connect. Change before the first TestFlight upload if you prefer another.
  appId: 'work.kushman.sniffari',
  appName: 'Sniffari',
  webDir: 'dist',
  backgroundColor: '#16131c',
  ios: {
    contentInset: 'never',
    backgroundColor: '#16131c',
  },
};

export default config;
