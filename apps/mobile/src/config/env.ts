import Constants from 'expo-constants';

/**
 * Resolves the RELAY API base URL.
 *
 * Priority:
 *   1. EXPO_PUBLIC_API_URL environment variable (set per build/environment)
 *   2. expo.extra.apiUrl in app.json (default local dev server)
 *
 * The local API from `services/api` listens on http://127.0.0.1:8787. On a
 * physical device, 127.0.0.1 points at the phone, so set EXPO_PUBLIC_API_URL
 * to your machine's LAN IP (e.g. http://192.168.1.20:8787).
 */
export function getApiUrl(): string {
  const fromEnv = process.env.EXPO_PUBLIC_API_URL;
  if (fromEnv) return fromEnv.replace(/\/$/, '');

  const fromExtra = (Constants.expoConfig?.extra as { apiUrl?: string } | undefined)?.apiUrl;
  return (fromExtra ?? 'http://127.0.0.1:8787').replace(/\/$/, '');
}

export interface DispatcherLocation {
  lat: number;
  lon: number;
}

/**
 * Fixed position of the dispatch centre, used to show the resident how far
 * their phone is from dispatch. Returns null when not configured or invalid.
 */
export function getDispatcherLocation(): DispatcherLocation | null {
  const lat = Number.parseFloat(process.env.EXPO_PUBLIC_DISPATCHER_LAT ?? '');
  const lon = Number.parseFloat(process.env.EXPO_PUBLIC_DISPATCHER_LON ?? '');
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return { lat, lon };
}

/**
 * Demo bearer token for authenticating to the API outside loopback. These are
 * shared demo tokens per the API contract, not verified device identity.
 */
export function getDeviceToken(): string | undefined {
  return process.env.EXPO_PUBLIC_DEVICE_TOKEN || undefined;
}
