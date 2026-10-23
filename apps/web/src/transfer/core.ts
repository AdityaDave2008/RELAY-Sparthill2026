// Codex's QR packet code (encodeTransfer, TransferReceiver) is not on this
// branch yet. A namespace import keeps the app loading with or without it;
// the transfer screen says so instead of crashing. Replace with direct imports
// from '@relay/core' once packages/relay-core/src/transport.ts is merged.
import * as core from '@relay/core';
import type { MessageStore } from '@relay/core';

export interface ReceiveReport {
  added: string[];
  rejected: { id: string; reason: string }[];
}
export type TransferProgress =
  | { complete: false; received: number; total: number }
  | { complete: true; received: number; total: number; report: ReceiveReport };

interface Transport {
  encodeTransfer(store: MessageStore, options?: { ids?: string[] }): Promise<string[]>;
  TransferReceiver: new (store: MessageStore) => { accept(text: string): Promise<TransferProgress> };
}

const t = core as unknown as Partial<Transport>;

export const transportAvailable = typeof t.encodeTransfer === 'function' && typeof t.TransferReceiver === 'function';

export function encodeTransfer(store: MessageStore, options?: { ids?: string[] }): Promise<string[]> {
  if (!t.encodeTransfer) throw new Error('QR transport is not in this build yet');
  return t.encodeTransfer(store, options);
}

export function createReceiver(store: MessageStore): { accept(text: string): Promise<TransferProgress> } {
  if (!t.TransferReceiver) return { accept: () => Promise.reject(new Error('QR transport is not in this build yet')) };
  return new t.TransferReceiver(store);
}
