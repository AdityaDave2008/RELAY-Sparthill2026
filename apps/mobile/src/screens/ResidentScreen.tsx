import { type JSX, useCallback, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { createMessage, type RelayMessage } from '@relay/core';

import { useRelay } from '../relay/useRelay';

/**
 * Minimal resident screen: compose a help request, see the local outbox, and
 * sync with the gateway. Camera/QR transfer and map UI are intentionally left
 * as integration points (see services/api/README.md ownership notes).
 */
function formatTime(epochMs: number): string {
  const date = new Date(epochMs);
  // Local date + time, e.g. "Oct 23, 4:07 PM".
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function ResidentScreen(): JSX.Element {
  const { ready, deviceId, messages, pendingIds, error, syncing, lastSync, addMessage, sync } =
    useRelay();
  const [body, setBody] = useState('');

  const submit = useCallback(() => {
    if (!deviceId || !body.trim()) return;
    try {
      const message = createMessage({
        kind: 'help_request',
        originDeviceId: deviceId,
        body: body.trim(),
      });
      addMessage(message);
      setBody('');
    } catch {
      // createMessage validates; invalid input is simply not added.
    }
  }, [addMessage, body, deviceId]);

  if (!ready) {
    return (
      <View style={styles.center}>
        <ActivityIndicator />
        <Text style={styles.muted}>Opening local store…</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Request help</Text>
      <Text style={styles.muted}>Device: {deviceId}</Text>

      <TextInput
        style={styles.input}
        placeholder="Describe what you need (water, medical, shelter…)"
        value={body}
        onChangeText={setBody}
        multiline
        maxLength={1000}
      />

      <Pressable style={styles.primary} onPress={submit} disabled={!body.trim()}>
        <Text style={styles.primaryText}>Save help request</Text>
      </Pressable>

      <Pressable style={styles.secondary} onPress={sync} disabled={syncing}>
        <Text style={styles.secondaryText}>{syncing ? 'Syncing…' : 'Sync with gateway'}</Text>
      </Pressable>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {lastSync ? (
        <Text style={styles.muted}>
          Uploaded {lastSync.uploadedIds.length} · received {lastSync.receivedIds.length}
          {lastSync.rejected.length > 0 ? ` · rejected ${lastSync.rejected.length}` : ''}
        </Text>
      ) : null}

      <Text style={styles.subheading}>Local messages ({messages.length})</Text>
      <FlatList
        data={messages}
        keyExtractor={(item: RelayMessage) => item.id}
        renderItem={({ item }) => {
          const pending = pendingIds.has(item.id);
          return (
            <View style={styles.row}>
              <View style={styles.rowHeader}>
                <Text style={styles.rowKind}>{item.kind}</Text>
                <Text style={styles.rowTime}>{formatTime(item.createdAt)}</Text>
              </View>
              <Text style={styles.rowBody} numberOfLines={2}>
                {item.title ? `${item.title} — ` : ''}
                {item.body}
              </Text>
              <Text style={pending ? styles.badgePending : styles.badgeUploaded}>
                {pending ? '● saved locally' : '✓ uploaded'}
              </Text>
            </View>
          );
        }}
        ListEmptyComponent={<Text style={styles.muted}>No messages yet.</Text>}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20, gap: 10 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8 },
  heading: { fontSize: 24, fontWeight: '700' },
  subheading: { fontSize: 18, fontWeight: '600', marginTop: 12 },
  muted: { color: '#6b7280' },
  error: { color: '#b91c1c' },
  input: {
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 8,
    padding: 12,
    minHeight: 72,
    textAlignVertical: 'top',
  },
  primary: { backgroundColor: '#b91c1c', padding: 14, borderRadius: 8, alignItems: 'center' },
  primaryText: { color: 'white', fontWeight: '700' },
  secondary: { borderWidth: 1, borderColor: '#b91c1c', padding: 14, borderRadius: 8, alignItems: 'center' },
  secondaryText: { color: '#b91c1c', fontWeight: '700' },
  row: { paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#f3f4f6', gap: 2 },
  rowHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  rowKind: { fontSize: 12, textTransform: 'uppercase', color: '#6b7280' },
  rowTime: { fontSize: 12, color: '#9ca3af' },
  rowBody: { fontSize: 15 },
  badgePending: { fontSize: 12, color: '#b45309' },
  badgeUploaded: { fontSize: 12, color: '#15803d' },
});
