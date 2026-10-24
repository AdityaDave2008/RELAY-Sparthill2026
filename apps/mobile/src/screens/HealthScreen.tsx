import { type JSX, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';

import {
  BLOOD_TYPES,
  CRITICAL_NEEDS,
  HEALTH_LIMITS,
  type HealthProfile,
} from '../relay/health';

interface Props {
  ready: boolean;
  profile: HealthProfile;
  loadError: string | null;
  onSave: (next: HealthProfile) => Promise<void>;
  onClear: () => Promise<void>;
}

export function HealthScreen({ ready, profile, loadError, onSave, onClear }: Props): JSX.Element {
  const [draft, setDraft] = useState<HealthProfile>(profile);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);

  // Load the saved profile into the form once it arrives (or after clearing).
  useEffect(() => setDraft(profile), [profile]);

  const dirty = JSON.stringify(draft) !== JSON.stringify(profile);
  const set = <K extends keyof HealthProfile>(key: K, value: HealthProfile[K]) => {
    setDraft((current) => ({ ...current, [key]: value }));
    setMessage(null);
  };

  const save = async () => {
    setSaving(true);
    try {
      await onSave(draft);
      setMessage({ kind: 'ok', text: 'Saved on this phone.' });
    } catch (saveError) {
      setMessage({ kind: 'error', text: `Not saved: ${String(saveError)}` });
    } finally {
      setSaving(false);
    }
  };

  const confirmClear = () =>
    Alert.alert('Clear health info?', 'This removes your health info from this phone.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Clear',
        style: 'destructive',
        onPress: () => {
          onClear()
            .then(() => setMessage({ kind: 'ok', text: 'Health info cleared.' }))
            .catch((clearError) =>
              setMessage({ kind: 'error', text: `Could not clear: ${String(clearError)}` }),
            );
        },
      },
    ]);

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
      automaticallyAdjustKeyboardInsets
    >
      <View style={styles.headerBlock}>
        <Text style={styles.title}>Health info</Text>
        <Text style={styles.subtitle}>
          Stored only on this phone. Dispatch sees it only when you choose to attach it to a help
          request. Fill in what you are comfortable sharing.
        </Text>
      </View>

      {loadError && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{loadError}</Text>
        </View>
      )}

      <Field label="Full name">
        <TextInput
          style={styles.input}
          value={draft.fullName}
          onChangeText={(v) => set('fullName', v)}
          maxLength={HEALTH_LIMITS.fullName}
          autoComplete="name"
          editable={ready}
        />
      </Field>

      <Field label="Age">
        <TextInput
          style={[styles.input, styles.short]}
          value={draft.age}
          onChangeText={(v) => set('age', v.replace(/\D/g, ''))}
          keyboardType="number-pad"
          maxLength={HEALTH_LIMITS.age}
          editable={ready}
        />
      </Field>

      <Field label="Blood type">
        <View style={styles.chips}>
          {BLOOD_TYPES.map((type) => {
            const selected = draft.bloodType === type;
            return (
              <Pressable
                key={type}
                style={[styles.chip, selected && styles.chipSelected]}
                onPress={() => set('bloodType', selected ? null : type)}
                accessibilityRole="radio"
                accessibilityState={{ checked: selected }}
              >
                <Text style={styles.chipText}>{type}</Text>
              </Pressable>
            );
          })}
        </View>
      </Field>

      <Field label="Critical needs">
        <View style={styles.chips}>
          {CRITICAL_NEEDS.map((need) => {
            const selected = draft.criticalNeeds.includes(need);
            return (
              <Pressable
                key={need}
                style={[styles.chip, selected && styles.chipSelected]}
                onPress={() =>
                  set(
                    'criticalNeeds',
                    selected
                      ? draft.criticalNeeds.filter((n) => n !== need)
                      : [...draft.criticalNeeds, need],
                  )
                }
                accessibilityRole="checkbox"
                accessibilityState={{ checked: selected }}
              >
                <Text style={styles.chipText}>{need}</Text>
              </Pressable>
            );
          })}
        </View>
      </Field>

      <Field label="Medical conditions">
        <TextInput
          style={[styles.input, styles.multiline]}
          value={draft.conditions}
          onChangeText={(v) => set('conditions', v)}
          maxLength={HEALTH_LIMITS.conditions}
          multiline
          placeholder="e.g. Type 1 diabetes, asthma"
          placeholderTextColor="#9ca3af"
          editable={ready}
        />
      </Field>

      <Field label="Medications">
        <TextInput
          style={[styles.input, styles.multiline]}
          value={draft.medications}
          onChangeText={(v) => set('medications', v)}
          maxLength={HEALTH_LIMITS.medications}
          multiline
          placeholder="e.g. Insulin 3x daily, albuterol inhaler"
          placeholderTextColor="#9ca3af"
          editable={ready}
        />
      </Field>

      <Field label="Allergies">
        <TextInput
          style={[styles.input, styles.multiline]}
          value={draft.allergies}
          onChangeText={(v) => set('allergies', v)}
          maxLength={HEALTH_LIMITS.allergies}
          multiline
          placeholder="e.g. Penicillin, peanuts"
          placeholderTextColor="#9ca3af"
          editable={ready}
        />
      </Field>

      <Field label="Emergency contact">
        <View style={styles.stack}>
          <TextInput
            style={styles.input}
            value={draft.contactName}
            onChangeText={(v) => set('contactName', v)}
            maxLength={HEALTH_LIMITS.contactName}
            placeholder="Name"
            placeholderTextColor="#9ca3af"
            editable={ready}
          />
          <TextInput
            style={styles.input}
            value={draft.contactPhone}
            onChangeText={(v) => set('contactPhone', v)}
            maxLength={HEALTH_LIMITS.contactPhone}
            keyboardType="phone-pad"
            placeholder="Phone"
            placeholderTextColor="#9ca3af"
            editable={ready}
          />
        </View>
      </Field>

      <Field label="Other notes">
        <TextInput
          style={[styles.input, styles.multiline]}
          value={draft.notes}
          onChangeText={(v) => set('notes', v)}
          maxLength={HEALTH_LIMITS.notes}
          multiline
          placeholder="e.g. Pacemaker, needs refrigerated medicine"
          placeholderTextColor="#9ca3af"
          editable={ready}
        />
      </Field>

      {message && (
        <Text style={message.kind === 'ok' ? styles.okText : styles.errorText}>{message.text}</Text>
      )}

      <Pressable
        style={[styles.saveBtn, (!ready || !dirty || saving) && styles.disabled]}
        disabled={!ready || !dirty || saving}
        onPress={() => void save()}
        accessibilityRole="button"
      >
        <Text style={styles.saveText}>{saving ? 'Saving…' : dirty ? 'Save health info' : 'Saved'}</Text>
      </Pressable>

      <Pressable style={styles.clearBtn} onPress={confirmClear} disabled={!ready} accessibilityRole="button">
        <Text style={styles.clearText}>Clear health info</Text>
      </Pressable>
    </ScrollView>
  );
}

function Field({ label, children }: { label: string; children: JSX.Element }): JSX.Element {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  content: { padding: 20, gap: 18, paddingBottom: 40 },
  headerBlock: { gap: 6 },
  title: { fontSize: 30, fontWeight: '800', color: '#0f172a' },
  subtitle: { fontSize: 16, color: '#475569', lineHeight: 22 },
  field: { gap: 8 },
  label: { fontSize: 16, fontWeight: '700', color: '#0f172a' },
  stack: { gap: 10 },
  input: { borderWidth: 1, borderColor: '#cbd5e1', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, color: '#0f172a', backgroundColor: 'white' },
  short: { width: 100 },
  multiline: { minHeight: 72, textAlignVertical: 'top' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { paddingVertical: 9, paddingHorizontal: 14, borderRadius: 999, borderWidth: 1, borderColor: '#cbd5e1', backgroundColor: 'white' },
  chipSelected: { borderColor: '#0f172a', borderWidth: 2, backgroundColor: '#f1f5f9' },
  chipText: { fontSize: 15, fontWeight: '600', color: '#0f172a' },
  errorBanner: { borderRadius: 10, backgroundColor: '#fef2f2', borderWidth: 1, borderColor: '#fecaca', padding: 12 },
  errorText: { color: '#991b1b', fontSize: 14, lineHeight: 20 },
  okText: { color: '#047857', fontSize: 14, fontWeight: '600' },
  saveBtn: { backgroundColor: '#0f172a', paddingVertical: 16, borderRadius: 12, alignItems: 'center' },
  saveText: { color: 'white', fontSize: 17, fontWeight: '700' },
  disabled: { opacity: 0.5 },
  clearBtn: { paddingVertical: 12, alignItems: 'center' },
  clearText: { color: '#b91c1c', fontSize: 15, fontWeight: '600' },
});
