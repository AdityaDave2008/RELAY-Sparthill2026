import { useCallback, useEffect, useRef, useState } from 'react';
import {
  MessageStore,
  syncWithGateway,
  type GatewaySyncReport,
  type RelayMessage,
} from '@relay/core';

import { getApiUrl, getDeviceToken } from '../config/env';
import { getOrCreateDeviceId } from './deviceId';
import { asyncStoragePersistence } from './persistence';

export interface RelayState {
  ready: boolean;
  deviceId: string | null;
  messages: RelayMessage[];
  /** IDs of messages not yet accepted by the gateway (still pending upload). */
  pendingIds: Set<string>;
  error: string | null;
  syncing: boolean;
  lastSync: GatewaySyncReport | null;
}

/**
 * Opens the durable MessageStore, exposes the current messages, and provides a
 * sync action against the RELAY REST API. This is the thin glue between
 * @relay/core and the React Native UI; screens read `messages` and call `sync`.
 */
export function useRelay(): RelayState & {
  addMessage: (message: RelayMessage) => void;
  sync: () => Promise<void>;
} {
  const storeRef = useRef<MessageStore | null>(null);
  const [ready, setReady] = useState(false);
  const [deviceId, setDeviceId] = useState<string | null>(null);
  const [messages, setMessages] = useState<RelayMessage[]>([]);
  const [pendingIds, setPendingIds] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [lastSync, setLastSync] = useState<GatewaySyncReport | null>(null);

  const refresh = useCallback(() => {
    const store = storeRef.current;
    if (!store) return;
    setMessages(store.list());
    // pendingUpload() returns messages still awaiting gateway acceptance;
    // anything not in that set has been uploaded.
    setPendingIds(new Set(store.pendingUpload().map((m) => m.id)));
  }, []);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const persistence = asyncStoragePersistence('relay:messages', (writeError) =>
          setError(`Storage write failed: ${String(writeError)}`),
        );
        await persistence.loadSnapshot();
        const id = await getOrCreateDeviceId();
        if (!active) return;
        storeRef.current = MessageStore.open(persistence);
        setDeviceId(id);
        setMessages(storeRef.current.list());
        setReady(true);
      } catch (openError) {
        // Opening a corrupt snapshot throws; surface it rather than pretending
        // the local store is healthy.
        if (active) setError(`Could not open local store: ${String(openError)}`);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const addMessage = useCallback(
    (message: RelayMessage) => {
      const store = storeRef.current;
      if (!store) return;
      const result = store.add(message);
      if (result !== 'added' && result !== 'duplicate') {
        setError(`Message not saved: ${result}`);
        return;
      }
      refresh();
    },
    [refresh],
  );

  const sync = useCallback(async () => {
    const store = storeRef.current;
    if (!store || !deviceId) return;
    setSyncing(true);
    setError(null);
    try {
      const report = await syncWithGateway(store, {
        baseUrl: getApiUrl(),
        deviceId,
        token: getDeviceToken(),
      });
      setLastSync(report);
      refresh();
    } catch (syncError) {
      setError(`Sync failed: ${String(syncError)}`);
    } finally {
      setSyncing(false);
    }
  }, [deviceId, refresh]);

  return { ready, deviceId, messages, pendingIds, error, syncing, lastSync, addMessage, sync };
}
