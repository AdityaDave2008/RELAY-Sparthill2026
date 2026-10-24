import { type JSX, useCallback, useEffect, useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import * as Location from 'expo-location';
import { createMessage, type GeoPoint, type RelayMessage } from '@relay/core';

import { getDispatcherLocation, type DispatcherLocation } from '../config/env';
import { useRelay } from '../relay/useRelay';
import { NEED_LABEL, NEEDS, type Need } from '../relay/contract';
import { composeRequestBody } from '../relay/health';

const NEED_ICON: Record<Need, { glyph: string; color: string }> = {
  water: { glyph: '💧', color: '#2563eb' },
  food: { glyph: '🍲', color: '#b45309' },
  medical: { glyph: '✚', color: '#dc2626' },
  shelter: { glyph: '🏠', color: '#15803d' },
  evacuation: { glyph: '🚶', color: '#15803d' },
  power: { glyph: '⚡', color: '#ca8a04' },
};

const REJECTION_LABEL: Record<string, string> = {
  invalid: 'The request format was invalid.',
  expired: 'The request expired before it reached dispatch.',
  conflict: 'The request ID conflicts with another message.',
  unauthorized_kind: 'The gateway did not allow this message type.',
  invalid_timestamp: 'This phone’s clock appears incorrect. Check the date and time, then try again.',
};

type Gps =
  | { status: 'idle' | 'locating' }
  | { status: 'fixed'; point: GeoPoint }
  | { status: 'error'; message: string };

function useGps(): [Gps, () => void] {
  const [gps, setGps] = useState<Gps>({ status: 'idle' });

  const locate = useCallback(() => {
    let cancelled = false;
    setGps((current) => (current.status === 'fixed' ? current : { status: 'locating' }));
    void (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (cancelled) return;
        if (status !== 'granted') {
          setGps({ status: 'error', message: 'Location permission was denied.' });
          return;
        }
        const position = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        if (cancelled) return;
        setGps({
          status: 'fixed',
          point: {
            lat: position.coords.latitude,
            lon: position.coords.longitude,
            accuracyM: Math.round(position.coords.accuracy ?? 999),
          },
        });
      } catch {
        if (!cancelled) setGps({ status: 'error', message: 'Could not get a location fix.' });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return [gps, locate];
}

/** Great-circle (haversine) distance in meters between two coordinates. */
function distanceMeters(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const R = 6_371_000;
  const rad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

function formatDistance(meters: number): string {
  if (meters < 1000) return `${Math.round(meters)} m`;
  return `${(meters / 1000).toFixed(meters < 10_000 ? 1 : 0)} km`;
}

function formatTime(epochMs: number): string {
  return new Date(epochMs).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function requestSummary(message: RelayMessage): string {
  const [, ...rest] = message.body.split('\n');
  const notes = rest.join('\n').split('\n\nHEALTH (shared by resident):')[0].trim();
  const withHealth = message.body.includes('HEALTH (shared by resident):');
  if (notes && !notes.startsWith('HEALTH (shared by resident):')) {
    return withHealth ? `${notes}\n+ health info attached` : notes;
  }
  const firstLine = message.body.split('\n')[0] ?? '';
  const header = firstLine.replace(/^NEEDS: /, 'Needs: ').replace(' | PEOPLE: ', ' · People: ');
  return withHealth ? `${header}\n+ health info attached` : header;
}

export function ResidentScreen({
  healthSummary,
  onEditHealth,
}: {
  /** One-line health summary from the Health tab, or null if not filled in. */
  healthSummary: string | null;
  onEditHealth: () => void;
}): JSX.Element {
  const {
    ready,
    deviceId,
    messages,
    pendingIds,
    rejectedById,
    error,
    syncError,
    refreshing,
    lastSuccessAt,
    addMessage,
    sync,
  } = useRelay();
  const [needs, setNeeds] = useState<Need[]>([]);
  const [people, setPeople] = useState<number | null>(null);
  const [notes, setNotes] = useState('');
  const [gps, locate] = useGps();
  const [submissionError, setSubmissionError] = useState<string | null>(null);
  const [submittedId, setSubmittedId] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [attachHealth, setAttachHealth] = useState(true);
  const dispatcher = useMemo(getDispatcherLocation, []);

  useEffect(() => locate(), [locate]);

  const ownRequests = useMemo(
    () =>
      messages
        .filter((message) => message.kind === 'help_request' && message.originDeviceId === deviceId)
        .sort((a, b) => b.createdAt - a.createdAt),
    [deviceId, messages],
  );
  const replies = useMemo(
    () =>
      messages
        .filter(
          (message) =>
            message.kind === 'ack' &&
            message.recipientDeviceId === deviceId &&
            typeof message.replyTo === 'string',
        )
        .sort((a, b) => b.createdAt - a.createdAt),
    [deviceId, messages],
  );
  const repliesByRequest = useMemo(
    () => new Map(replies.map((reply) => [reply.replyTo!, reply])),
    [replies],
  );
  const warnings = useMemo(
    () =>
      messages
        .filter((message) => message.kind === 'warning' && message.expiresAt > Date.now())
        .sort((a, b) => b.createdAt - a.createdAt),
    [messages],
  );

  const toggle = (need: Need) =>
    setNeeds((current) =>
      current.includes(need) ? current.filter((item) => item !== need) : [...current, need],
    );

  const canSend =
    ready && !!deviceId && !sending && (needs.length > 0 || notes.trim().length > 0);

  const send = useCallback(async () => {
    if (!deviceId || sending) return;
    setSending(true);
    setSubmissionError(null);
    try {
      const message = createMessage({
        kind: 'help_request',
        originDeviceId: deviceId,
        body: composeRequestBody(needs, people, notes, attachHealth ? healthSummary : null),
        ...(gps.status === 'fixed' ? { location: gps.point } : {}),
      });
      const result = await addMessage(message);
      if (result !== 'added' && result !== 'duplicate') {
        setSubmissionError(
          result === 'storage_failed'
            ? 'The request could not be safely stored. Your form has been kept; check phone storage and try again.'
            : `The request was not saved (${result.replaceAll('_', ' ')}).`,
        );
        return;
      }
      setSubmittedId(message.id);
      setNeeds([]);
      setPeople(null);
      setNotes('');
      void sync();
    } catch (sendError) {
      setSubmissionError(`The request was not created: ${String(sendError)}`);
    } finally {
      setSending(false);
    }
  }, [addMessage, attachHealth, deviceId, gps, healthSummary, needs, notes, people, sending, sync]);

  const submittedReply = submittedId ? repliesByRequest.get(submittedId) : undefined;
  const submittedRejection = submittedId ? rejectedById[submittedId] : undefined;
  const statusText = !ready
    ? 'Opening saved messages…'
    : submittedReply
      ? 'A dispatcher replied to your request.'
      : submittedRejection
        ? REJECTION_LABEL[submittedRejection] ?? `Dispatch rejected the request: ${submittedRejection}`
        : submittedId && pendingIds.has(submittedId)
          ? 'Saved on this phone. Will send when dispatch is reachable.'
          : submittedId
            ? 'Reached dispatch.'
            : syncError
              ? lastSuccessAt
                ? `Offline. Last updated ${formatTime(lastSuccessAt)}`
                : 'Offline. Retrying automatically.'
              : lastSuccessAt
                ? `Updated ${formatTime(lastSuccessAt)}`
                : 'Connecting to dispatch…';

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <View style={styles.statusRow}>
        <Text style={styles.updated}>{statusText}</Text>
        <Pressable
          style={styles.refreshBtn}
          disabled={!ready || refreshing}
          onPress={() => void sync({ manual: true })}
          accessibilityRole="button"
          accessibilityLabel="Check for dispatcher updates"
        >
          <Text style={styles.refreshText}>{refreshing ? 'Checking…' : 'Refresh'}</Text>
        </Pressable>
      </View>

      {(error || submissionError) && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{submissionError ?? error}</Text>
        </View>
      )}

      <View style={styles.headerBlock}>
        <Text style={styles.title}>Ask for help</Text>
        <Text style={styles.subtitle}>
          Works without signal. Your request is stored on this phone and sent when this phone
          reconnects.
        </Text>
      </View>

      <DispatcherUpdates warnings={warnings} replies={replies} />

      <Text style={styles.sectionTitle}>What do you need?</Text>
      <View style={styles.chips}>
        {NEEDS.map((need) => {
          const selected = needs.includes(need);
          const icon = NEED_ICON[need];
          return (
            <Pressable
              key={need}
              onPress={() => toggle(need)}
              style={[styles.chip, selected && styles.chipSelected]}
              accessibilityRole="button"
              accessibilityState={{ selected }}
            >
              <Text style={[styles.chipIcon, { color: icon.color }]}>{icon.glyph}</Text>
              <Text style={styles.chipLabel}>{NEED_LABEL[need]}</Text>
            </Pressable>
          );
        })}
      </View>

      <Text style={styles.sectionTitle}>How many people?</Text>
      <View style={styles.counter}>
        <Pressable
          style={styles.counterBtn}
          onPress={() => setPeople((current) => Math.max(1, (current ?? 1) - 1))}
          accessibilityLabel="Fewer people"
        >
          <Text style={styles.counterBtnText}>−</Text>
        </Pressable>
        <View style={styles.counterValueBox}>
          <TextInput
            style={styles.counterValue}
            keyboardType="number-pad"
            value={people === null ? '' : String(people)}
            placeholder="?"
            placeholderTextColor="#9ca3af"
            onChangeText={(text) => {
              const value = Number.parseInt(text, 10);
              setPeople(Number.isFinite(value) ? Math.max(1, value) : null);
            }}
            accessibilityLabel="Number of people"
          />
        </View>
        <Pressable
          style={styles.counterBtn}
          onPress={() => setPeople((current) => (current ?? 0) + 1)}
          accessibilityLabel="More people"
        >
          <Text style={styles.counterBtnText}>+</Text>
        </Pressable>
      </View>

      <Text style={styles.fieldLabel}>Tell us more</Text>
      <TextInput
        style={styles.textarea}
        value={notes}
        onChangeText={setNotes}
        maxLength={700}
        multiline
        placeholder="e.g. 25 people at the church on Elm St. Running out of drinking water. One person needs insulin."
        placeholderTextColor="#6b7280"
      />

      <Text style={styles.sectionTitle}>Distance from dispatch</Text>
      <LocationBlock gps={gps} dispatcher={dispatcher} onRetry={locate} />

      <Text style={styles.sectionTitle}>Health info</Text>
      {healthSummary ? (
        <Pressable
          style={styles.healthRow}
          onPress={() => setAttachHealth((v) => !v)}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: attachHealth }}
        >
          <Text style={styles.checkbox}>{attachHealth ? '☑' : '☐'}</Text>
          <View style={styles.gpsBody}>
            <Text style={styles.gpsLabel}>Attach my health info to this request</Text>
            <Text style={styles.gpsAccuracy} numberOfLines={3}>
              {healthSummary.replace('HEALTH (shared by resident): ', '')}
            </Text>
          </View>
        </Pressable>
      ) : (
        <Pressable style={styles.healthRow} onPress={onEditHealth} accessibilityRole="button">
          <Text style={styles.checkbox}>✚</Text>
          <Text style={[styles.gpsPending, styles.link]}>
            No health info saved. Add it in the Health tab so dispatch knows about medical needs.
          </Text>
        </Pressable>
      )}

      <Pressable
        style={[styles.sendBtn, !canSend && styles.buttonDisabled]}
        disabled={!canSend}
        onPress={() => void send()}
        accessibilityRole="button"
      >
        <Text style={styles.sendBtnText}>{sending ? 'Saving request…' : 'Send request'}</Text>
      </Pressable>

      {ownRequests.length > 0 && (
        <View style={styles.sectionBlock}>
          <Text style={styles.sectionTitle}>Your requests</Text>
          {ownRequests.map((request) => {
            const reply = repliesByRequest.get(request.id);
            const rejection = rejectedById[request.id];
            const pending = pendingIds.has(request.id);
            const state = reply
              ? 'Reply received'
              : rejection
                ? REJECTION_LABEL[rejection] ?? `Gateway rejected: ${rejection}`
                : pending
                  ? 'Saved locally · waiting to send'
                  : 'Reached dispatch · awaiting reply';
            return (
              <View key={request.id} style={styles.requestCard}>
                <Text style={styles.cardTime}>{formatTime(request.createdAt)}</Text>
                <Text style={styles.cardBody}>{requestSummary(request)}</Text>
                <Text style={[styles.requestState, rejection && styles.requestStateError]}>{state}</Text>
              </View>
            );
          })}
        </View>
      )}

      <Text style={styles.footer}>
        For life-threatening emergencies, call your local emergency number if you can.
      </Text>
    </ScrollView>
  );
}

function DispatcherUpdates({
  warnings,
  replies,
}: {
  warnings: RelayMessage[];
  replies: RelayMessage[];
}): JSX.Element | null {
  if (warnings.length === 0 && replies.length === 0) return null;

  return (
    <View style={styles.sectionBlock}>
      <Text style={styles.sectionTitle}>Updates from dispatch</Text>
      {warnings.map((warning) => (
        <View key={warning.id} style={styles.warningCard}>
          <Text style={styles.warningEyebrow}>PUBLIC WARNING</Text>
          <Text style={styles.cardTitle}>{warning.title ?? 'Public warning'}</Text>
          <Text style={styles.cardBody}>{warning.body}</Text>
          <Text style={styles.cardTime}>
            Issued {formatTime(warning.createdAt)} · expires {formatTime(warning.expiresAt)}
          </Text>
        </View>
      ))}
      {replies.map((reply) => (
        <View key={reply.id} style={styles.replyCard}>
          <Text style={styles.replyEyebrow}>REPLY FROM DISPATCH</Text>
          <Text style={styles.cardBody}>{reply.body}</Text>
          <Text style={styles.cardTime}>{formatTime(reply.createdAt)}</Text>
        </View>
      ))}
    </View>
  );
}

function LocationBlock({
  gps,
  dispatcher,
  onRetry,
}: {
  gps: Gps;
  dispatcher: DispatcherLocation | null;
  onRetry: () => void;
}): JSX.Element {
  if (gps.status !== 'fixed') {
    return (
      <View style={styles.gps}>
        <Text style={styles.gpsPin}>📍</Text>
        <Text style={styles.gpsPending}>
          {gps.status === 'error'
            ? `${gps.message} Describe where you are in the message instead.`
            : 'Finding your location… (works without internet)'}
        </Text>
        {gps.status === 'error' && (
          <Pressable style={styles.retryBtn} onPress={onRetry}>
            <Text style={styles.retryText}>Retry</Text>
          </Pressable>
        )}
      </View>
    );
  }

  const accuracy = gps.point.accuracyM ?? 999;
  const rough = accuracy > 100;
  return (
    <View style={styles.gps}>
      <Text style={styles.gpsPin}>📍</Text>
      <View style={styles.gpsBody}>
        {dispatcher ? (
          <Text style={styles.distance}>{formatDistance(distanceMeters(dispatcher, gps.point))}</Text>
        ) : (
          <Text style={styles.gpsLabel}>Dispatch location not configured</Text>
        )}
        <Text style={styles.gpsAccuracy}>
          Your position ±{accuracy} m
          {rough ? '. Rough fix, please describe where you are.' : ''}
        </Text>
      </View>
      <Pressable style={styles.retryBtn} onPress={onRetry} accessibilityLabel="Update location">
        <Text style={styles.retryText}>Update</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  content: { padding: 20, gap: 16, paddingBottom: 40 },
  statusRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  updated: { color: '#6b7280', fontSize: 14, flex: 1 },
  refreshBtn: { paddingVertical: 7, paddingHorizontal: 12, borderRadius: 8, backgroundColor: '#e2e8f0' },
  refreshText: { color: '#0f172a', fontSize: 14, fontWeight: '700' },
  buttonDisabled: { opacity: 0.5 },
  errorBanner: { borderRadius: 10, backgroundColor: '#fef2f2', borderWidth: 1, borderColor: '#fecaca', padding: 12 },
  errorText: { color: '#991b1b', fontSize: 14, lineHeight: 20 },
  headerBlock: { gap: 6 },
  title: { fontSize: 30, fontWeight: '800', color: '#0f172a' },
  subtitle: { fontSize: 16, color: '#475569', lineHeight: 22 },
  sectionBlock: { gap: 10 },
  sectionTitle: { fontSize: 20, fontWeight: '700', color: '#0f172a', marginTop: 4 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 12, paddingHorizontal: 18, borderRadius: 999, borderWidth: 1, borderColor: '#e2e8f0', backgroundColor: 'white' },
  chipSelected: { borderColor: '#0f172a', borderWidth: 2 },
  chipIcon: { fontSize: 18 },
  chipLabel: { fontSize: 16, fontWeight: '600', color: '#0f172a' },
  counter: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  counterBtn: { width: 56, height: 56, borderRadius: 12, borderWidth: 1, borderColor: '#e2e8f0', backgroundColor: 'white', alignItems: 'center', justifyContent: 'center' },
  counterBtnText: { fontSize: 24, fontWeight: '600', color: '#0f172a' },
  counterValueBox: { width: 84, height: 56, borderRadius: 12, borderWidth: 1, borderColor: '#e2e8f0', backgroundColor: 'white' },
  counterValue: { flex: 1, textAlign: 'center', fontSize: 20, fontWeight: '600', color: '#0f172a' },
  fieldLabel: { fontSize: 16, fontWeight: '600', color: '#0f172a' },
  textarea: { borderWidth: 1, borderColor: '#cbd5e1', borderRadius: 10, padding: 14, minHeight: 110, fontSize: 16, color: '#0f172a', backgroundColor: 'white', textAlignVertical: 'top' },
  gps: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 16, borderRadius: 12, backgroundColor: '#eef2f6' },
  gpsPin: { fontSize: 22 },
  gpsBody: { flex: 1, gap: 4 },
  gpsPending: { flex: 1, fontSize: 14, color: '#475569' },
  gpsLabel: { fontSize: 16, fontWeight: '700', color: '#0f172a' },
  distance: { fontSize: 24, fontWeight: '800', color: '#0f172a' },
  gpsAccuracy: { fontSize: 14, color: '#6b7280' },
  healthRow: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 16, borderRadius: 12, backgroundColor: '#eef2f6' },
  checkbox: { fontSize: 22, color: '#0f172a' },
  link: { color: '#1d4ed8' },
  retryBtn: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: 8, borderWidth: 1, borderColor: '#cbd5e1', backgroundColor: 'white' },
  retryText: { fontSize: 14, fontWeight: '600', color: '#0f172a' },
  sendBtn: { backgroundColor: '#ef7d5a', paddingVertical: 18, borderRadius: 12, alignItems: 'center', marginTop: 4 },
  sendBtnText: { color: 'white', fontSize: 18, fontWeight: '700' },
  warningCard: { gap: 7, padding: 14, borderRadius: 12, backgroundColor: '#fff7ed', borderWidth: 1, borderColor: '#fdba74' },
  warningEyebrow: { color: '#9a3412', fontSize: 12, fontWeight: '800' },
  replyCard: { gap: 7, padding: 14, borderRadius: 12, backgroundColor: '#ecfdf5', borderWidth: 1, borderColor: '#6ee7b7' },
  replyEyebrow: { color: '#047857', fontSize: 12, fontWeight: '800' },
  requestCard: { gap: 6, padding: 14, borderRadius: 12, backgroundColor: 'white', borderWidth: 1, borderColor: '#e2e8f0' },
  cardTitle: { color: '#0f172a', fontSize: 16, fontWeight: '800', flexShrink: 1 },
  cardBody: { color: '#334155', fontSize: 15, lineHeight: 21 },
  cardTime: { color: '#64748b', fontSize: 12 },
  requestState: { color: '#047857', fontSize: 13, fontWeight: '700' },
  requestStateError: { color: '#b91c1c' },
  footer: { fontSize: 14, color: '#64748b', textAlign: 'center' },
});
