import { useCallback, useEffect, useRef, useState } from 'react';
import NetInfo from '@react-native-community/netinfo';
import { AppState } from 'react-native';
import {
  MessageStore,
  syncWithGateway,
  type AddResult,
  type GatewaySyncReport,
  type RelayMessage,
} from '@relay/core';

import { getApiUrl, getDeviceToken } from '../config/env';
import { getOrCreateDeviceId } from './deviceId';
import { asyncStoragePersistence, type AsyncPersistence } from './persistence';

export type AddMessageResult = AddResult | 'not_ready' | 'storage_failed';

/** Upper bound for one sync, so the UI can never stay in a checking state. */
const SYNC_TIMEOUT_MS = 30_000;
const POLL_MS = 15_000;
const MAX_BACKOFF_MS = 120_000;

export interface RelayState {
  ready: boolean;
  deviceId: string | null;
  messages: RelayMessage[];
  /** IDs of messages not yet accepted by the gateway (still pending upload). */
  pendingIds: Set<string>;
  /** Most recent gateway rejection for each local message. */
  rejectedById: Record<string, string>;
  /** Storage or manual-refresh error worth showing prominently. */
  error: string | null;
  /** Last failed sync attempt (background or manual); cleared on success. */
  syncError: string | null;
  /** True only while a resident-initiated refresh is running. */
  refreshing: boolean;
  lastSync: GatewaySyncReport | null;
  lastSuccessAt: number | null;
}

/**
 * Owns the durable mobile message store and its gateway sync lifecycle.
 * Background syncs run after startup, while foregrounded and after a network
 * reconnect, backing off when dispatch is unreachable. They never block the
 * UI; only a manual refresh shows a checking state.
 */
export function useRelay(): RelayState & {
  addMessage: (message: RelayMessage) => Promise<AddMessageResult>;
  sync: (options?: { manual?: boolean }) => Promise<GatewaySyncReport | null>;
} {
  const storeRef = useRef<MessageStore | null>(null);
  const persistenceRef = useRef<AsyncPersistence | null>(null);
  const syncRef = useRef<Promise<GatewaySyncReport | null> | null>(null);
  const failuresRef = useRef(0);
  const mountedRef = useRef(true);
  const [ready, setReady] = useState(false);
  const [deviceId, setDeviceId] = useState<string | null>(null);
  const [messages, setMessages] = useState<RelayMessage[]>([]);
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());
  const [rejectedById, setRejectedById] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [lastSync, setLastSync] = useState<GatewaySyncReport | null>(null);
  const [lastSuccessAt, setLastSuccessAt] = useState<number | null>(null);

  useEffect(() => () => {
    mountedRef.current = false;
  }, []);

  const refresh = useCallback(() => {
    const store = storeRef.current;
    if (!store) return;
    setMessages(store.list());
    setPendingIds(new Set(store.pendingUpload().map((message) => message.id)));
  }, []);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const persistence = asyncStoragePersistence('relay:messages', (writeError) => {
          if (mountedRef.current) setError(`Storage write failed: ${String(writeError)}`);
        });
        await persistence.loadSnapshot();
        const id = await getOrCreateDeviceId();
        if (!active) return;
        persistenceRef.current = persistence;
        storeRef.current = MessageStore.open(persistence);
        setDeviceId(id);
        refresh();
        setReady(true);
      } catch (openError) {
        if (active) setError(`Could not open local store: ${String(openError)}`);
      }
    })();
    return () => {
      active = false;
    };
  }, [refresh]);

  const addMessage = useCallback(
    async (message: RelayMessage): Promise<AddMessageResult> => {
      const store = storeRef.current;
      const persistence = persistenceRef.current;
      if (!store || !persistence) return 'not_ready';

      setError(null);
      const result = store.add(message);
      if (result !== 'added' && result !== 'duplicate') {
        setError(`Message not saved: ${result}`);
        return result;
      }

      refresh();
      try {
        await persistence.flush();
        return result;
      } catch (writeError) {
        setError(`Request could not be saved on this phone: ${String(writeError)}`);
        return 'storage_failed';
      }
    },
    [refresh],
  );

  const runSync = useCallback((): Promise<GatewaySyncReport | null> => {
    const store = storeRef.current;
    if (!store || !deviceId) return Promise.resolve(null);
    if (syncRef.current) return syncRef.current;

    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error('dispatch did not respond in time')), SYNC_TIMEOUT_MS);
    });

    const task: Promise<GatewaySyncReport | null> = Promise.race([
      syncWithGateway(store, { baseUrl: getApiUrl(), deviceId, token: getDeviceToken() }),
      timeout,
    ])
      .then((report) => {
        failuresRef.current = 0;
        if (!mountedRef.current) return report;
        setLastSync(report);
        setLastSuccessAt(Date.now());
        setSyncError(null);
        setRejectedById((current) => {
          const next = { ...current };
          for (const id of report.uploadedIds) delete next[id];
          for (const rejection of report.rejected) next[rejection.id] = rejection.reason;
          return next;
        });
        refresh();
        return report;
      })
      .catch((syncFailure: unknown) => {
        failuresRef.current += 1;
        const message = syncFailure instanceof Error ? syncFailure.message : String(syncFailure);
        if (mountedRef.current) {
          setSyncError(message);
          // Messages may still have been partly uploaded before the failure.
          refresh();
        }
        return null;
      })
      .finally(() => {
        clearTimeout(timer);
        if (syncRef.current === task) syncRef.current = null;
      });

    syncRef.current = task;
    return task;
  }, [deviceId, refresh]);

  const sync = useCallback(
    async (options: { manual?: boolean } = {}): Promise<GatewaySyncReport | null> => {
      if (!options.manual) return runSync();
      setRefreshing(true);
      setError(null);
      try {
        const report = await runSync();
        if (!report && mountedRef.current) setError('Could not reach dispatch. Your requests stay saved on this phone.');
        return report;
      } finally {
        if (mountedRef.current) setRefreshing(false);
      }
    },
    [runSync],
  );

  useEffect(() => {
    if (!ready) return;

    let foreground = AppState.currentState === 'active';
    let online = true;
    let networkKnown = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let stopped = false;

    const schedule = () => {
      clearTimeout(timer);
      if (stopped) return;
      const backoff = Math.min(POLL_MS * 2 ** failuresRef.current, MAX_BACKOFF_MS);
      timer = setTimeout(tick, backoff);
    };
    const tick = () => {
      if (stopped) return;
      if (!foreground || !online) {
        schedule();
        return;
      }
      void runSync().finally(schedule);
    };
    const runNow = () => {
      failuresRef.current = 0;
      tick();
    };

    tick();
    const appStateSubscription = AppState.addEventListener('change', (state) => {
      const becameActive = !foreground && state === 'active';
      foreground = state === 'active';
      if (becameActive) runNow();
    });
    const unsubscribeNetwork = NetInfo.addEventListener((state) => {
      const nextOnline = state.isConnected !== false && state.isInternetReachable !== false;
      const reconnected = networkKnown && !online && nextOnline;
      online = nextOnline;
      networkKnown = true;
      if (reconnected) runNow();
    });

    return () => {
      stopped = true;
      clearTimeout(timer);
      appStateSubscription.remove();
      unsubscribeNetwork();
    };
  }, [ready, runSync]);

  return {
    ready,
    deviceId,
    messages,
    pendingIds,
    rejectedById,
    error,
    syncError,
    refreshing,
    lastSync,
    lastSuccessAt,
    addMessage,
    sync,
  };
}
