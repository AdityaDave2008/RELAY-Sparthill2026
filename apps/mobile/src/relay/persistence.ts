import AsyncStorage from '@react-native-async-storage/async-storage';
import type { SnapshotPersistence } from '@relay/core';

/**
 * Bridges @relay/core's synchronous SnapshotPersistence to React Native's
 * asynchronous AsyncStorage.
 *
 * The store writes to an in-memory snapshot synchronously, then serializes the
 * durable writes. Call flush() before telling the resident that a newly added
 * request is safely stored on the phone.
 */
export interface AsyncPersistence extends SnapshotPersistence {
  /** Load the persisted snapshot from AsyncStorage before opening the store. */
  loadSnapshot(): Promise<void>;
  /** Wait for every durable write requested so far. */
  flush(): Promise<void>;
}

export function asyncStoragePersistence(
  key = 'relay:messages',
  onWriteError?: (error: unknown) => void,
): AsyncPersistence {
  let cached: string | null = null;
  let writes: Promise<void> = Promise.resolve();

  return {
    async loadSnapshot(): Promise<void> {
      cached = await AsyncStorage.getItem(key);
    },
    read(): string | null {
      return cached;
    },
    write(snapshot: string): void {
      cached = snapshot;
      // Recover the queue after an earlier failure so later saves can retry.
      writes = writes
        .catch(() => undefined)
        .then(() => AsyncStorage.setItem(key, snapshot))
        .catch((error) => {
          onWriteError?.(error);
          throw error;
        });
    },
    flush(): Promise<void> {
      return writes;
    },
  };
}
