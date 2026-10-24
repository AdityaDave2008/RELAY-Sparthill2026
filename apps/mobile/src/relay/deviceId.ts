import AsyncStorage from '@react-native-async-storage/async-storage';

const DEVICE_ID_KEY = 'relay:device-id';

/**
 * Returns a stable per-install device ID, generating one on first launch.
 * This is a routing label used by the API and sync layer, not an authenticated
 * identity. crypto.randomUUID is provided by src/polyfills/randomUUID, loaded
 * in index.ts (Hermes/react-native-get-random-values do not supply it).
 */
export async function getOrCreateDeviceId(): Promise<string> {
  const existing = await AsyncStorage.getItem(DEVICE_ID_KEY);
  if (existing) return existing;
  const generated = `device-${crypto.randomUUID()}`;
  await AsyncStorage.setItem(DEVICE_ID_KEY, generated);
  return generated;
}
