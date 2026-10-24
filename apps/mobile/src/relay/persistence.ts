import AsyncStorage from '@react-native-async-storage/async-storage';
import type { SnapshotPersistence } from '@relay/core';

/**
 * Bridges @relay/core's synchronous SnapshotPersistence to React Native's
 * asynchronous AsyncStorage.
 *
 * MessageStore.open() expects read()/write() to be synchronous, but AsyncStorage
 * is promise-based. We hydrate the snapshot once at startup (await loadSnapshot),
 * keep the latest value in memory, and write through to AsyncStorage in the
 * background. The in-memory copy is the source of truth for a synchronous read();
 * AsyncStorage is the durable mirror.
 *
 * Use one active owner per storage key, exactly as the web localStorage adapter
 * requires. A failed durable write is surfaced via onWriteError so the UI can
 * avoid claiming a message was saved.
 */
export interface AsyncPersistence extends SnapshotPersistence {
  /** Load the persisted snapshot from AsyncStorage before opening the store. */
  loadSnapshot(): Promise<void>;
}

export function asyncStoragePersistence(
  key = 'relay:messages',
  onWriteError?: (error: unknown) => void,
): AsyncPersistence {
  let cached: string | null = null;

  return {
    async loadSnapshot(): Promise<void> {
      cached = await AsyncStorage.getItem(key);
    },
    read(): string | null {
      return cached;
    },
    write(snapshot: string): void {
      cached = snapshot;
      // Fire-and-forget durable write; report failures without blocking the store.
      AsyncStorage.setItem(key, snapshot).catch((error) => onWriteError?.(error));
    },
  };
}
