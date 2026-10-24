import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

/** Remind the resident to check their health info this often. */
export const HEALTH_REMINDER_INTERVAL_MS = 14 * 24 * 60 * 60 * 1000;

const DISMISSED_KEY = 'relay:health-reminder-dismissed-at:v1';
const RECHECK_MS = 60 * 60 * 1000;

/**
 * Decides whether to show the "check your health info" banner.
 *
 * The banner is due two weeks after the later of the last save and the last
 * time the resident closed the banner, so closing it snoozes it for another
 * two weeks and saving health info resets the clock. Profiles with no save
 * time are treated as due.
 */
export function useHealthReminder(
  updatedAt: number | null,
  enabled: boolean,
): { due: boolean; daysSinceUpdate: number | null; dismiss: () => void } {
  const [dismissedAt, setDismissedAt] = useState<number | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    let active = true;
    AsyncStorage.getItem(DISMISSED_KEY)
      .then((saved) => {
        const value = Number(saved);
        if (active && saved && Number.isSafeInteger(value) && value > 0) setDismissedAt(value);
      })
      .catch(() => undefined)
      .finally(() => active && setLoaded(true));
    return () => {
      active = false;
    };
  }, []);

  // Re-evaluate when the app returns to the foreground and hourly while open.
  useEffect(() => {
    const tick = () => setNow(Date.now());
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') tick();
    });
    const interval = setInterval(tick, RECHECK_MS);
    return () => {
      subscription.remove();
      clearInterval(interval);
    };
  }, []);

  const dismiss = useCallback(() => {
    const at = Date.now();
    setDismissedAt(at);
    // If this write fails the banner simply returns on the next launch.
    AsyncStorage.setItem(DISMISSED_KEY, String(at)).catch(() => undefined);
  }, []);

  const since = Math.max(updatedAt ?? 0, dismissedAt ?? 0);
  const due = enabled && loaded && now - since >= HEALTH_REMINDER_INTERVAL_MS;
  const daysSinceUpdate = updatedAt === null ? null : Math.floor((now - updatedAt) / 86_400_000);
  return { due, daysSinceUpdate, dismiss };
}
