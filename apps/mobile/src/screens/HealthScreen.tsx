import { type JSX, type ReactNode, useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';

import {
  BLOOD_TYPES,
  CRITICAL_NEEDS,
  HEALTH_LIMITS,
  NO_CRITICAL_NEEDS,
  validateHealth,
  type CriticalNeed,
  type HealthField,
  type HealthProfile,
  type HeightUnit,
  type WeightUnit,
  convertHeight,
  convertWeight,
} from '../relay/health';
import { useTheme, useThemedStyles } from '../ui/theme';

interface Props {
  /** onboarding: required before the main screen. edit: the Health info tab. */
  mode: 'onboarding' | 'edit';
  ready: boolean;
  profile: HealthProfile;
  loadError: string | null;
  onSave: (next: HealthProfile) => Promise<void>;
  onClear?: () => Promise<void>;
  /** A check-in reminder is showing: allow saving unchanged info to confirm it. */
  reminderDue?: boolean;
}

export function HealthScreen({ mode, ready, profile, loadError, onSave, onClear, reminderDue = false }: Props): JSX.Element {
  const onboarding = mode === 'onboarding';
  const theme = useTheme();
  const styles = useThemedStyles(baseStyles);
  const [draft, setDraft] = useState<HealthProfile>(profile);
  const [saving, setSaving] = useState(false);
  const [attempted, setAttempted] = useState(false);
  const [message, setMessage] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);

  // Load the saved profile into the form once it arrives (or after clearing).
  useEffect(() => setDraft(profile), [profile]);

  const errors = useMemo(() => validateHealth(draft), [draft]);
  const missing = Object.keys(errors).length;
  const dirty = JSON.stringify(draft) !== JSON.stringify(profile);
  // Show field errors only after the first submit attempt, then live.
  const errorFor = (field: HealthField) => (attempted ? errors[field] : undefined);

  const set = <K extends keyof HealthProfile>(key: K, value: HealthProfile[K]) => {
    setDraft((current) => ({ ...current, [key]: value }));
    setMessage(null);
  };

  const toggleNeed = (need: CriticalNeed) => {
    const selected = draft.criticalNeeds.includes(need);
    if (need === NO_CRITICAL_NEEDS) {
      set('criticalNeeds', selected ? [] : [NO_CRITICAL_NEEDS]);
      return;
    }
    const others = draft.criticalNeeds.filter((n) => n !== NO_CRITICAL_NEEDS);
    set('criticalNeeds', selected ? others.filter((n) => n !== need) : [...others, need]);
  };

  // Switching units converts what was already typed rather than clearing it.
  const setHeightUnit = (heightUnit: HeightUnit) => {
    if (heightUnit === draft.heightUnit) return;
    setDraft((current) => ({ ...current, heightUnit, ...convertHeight(current, heightUnit) }));
    setMessage(null);
  };
  const setWeightUnit = (weightUnit: WeightUnit) => {
    if (weightUnit === draft.weightUnit) return;
    setDraft((current) => ({ ...current, weightUnit, weight: convertWeight(current.weight, weightUnit) }));
    setMessage(null);
  };

  const save = async () => {
    setAttempted(true);
    if (missing > 0) {
      setMessage({
        kind: 'error',
        text: `${missing} field${missing > 1 ? 's need' : ' needs'} attention before you can continue.`,
      });
      return;
    }
    setSaving(true);
    try {
      await onSave(draft);
      setMessage(onboarding ? null : { kind: 'ok', text: 'Saved on this phone.' });
    } catch (saveError) {
      setMessage({ kind: 'error', text: `Not saved: ${String(saveError)}` });
    } finally {
      setSaving(false);
    }
  };

  const confirmClear = () =>
    Alert.alert(
      'Clear health info?',
      'This removes your health info from this phone. You will need to fill it in again before asking for help.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: () => {
            onClear?.().catch((clearError) =>
              setMessage({ kind: 'error', text: `Could not clear: ${String(clearError)}` }),
            );
          },
        },
      ],
    );

  const input = (field: HealthField) => [styles.input, errorFor(field) && styles.inputError];

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
      automaticallyAdjustKeyboardInsets
    >
      <View style={styles.headerBlock}>
        <Text style={styles.title}>{onboarding ? 'Before you start' : 'Health info'}</Text>
        <Text style={styles.subtitle}>
          {onboarding
            ? 'Fill in your health info so dispatch can help you faster. It is saved on this phone and sent with every help request.'
            : 'Saved on this phone and sent to dispatch with every help request you send.'}
        </Text>
        {onboarding && (
          <Text style={styles.emergency}>
            In a life-threatening emergency, call your local emergency number now if you can.
          </Text>
        )}
      </View>

      {loadError && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{loadError}</Text>
        </View>
      )}

      <Field label="Full name" error={errorFor('fullName')}>
        <TextInput
          style={input('fullName')}
          value={draft.fullName}
          onChangeText={(v) => set('fullName', v)}
          maxLength={HEALTH_LIMITS.fullName}
          autoComplete="name"
          editable={ready}
        />
      </Field>

      <Field label="Age" error={errorFor('age')}>
        <TextInput
          style={[input('age'), styles.short]}
          value={draft.age}
          onChangeText={(v) => set('age', v.replace(/\D/g, ''))}
          keyboardType="number-pad"
          maxLength={HEALTH_LIMITS.age}
          editable={ready}
        />
      </Field>

      <Field label="Height" error={errorFor('height')}>
        <View style={styles.measureRow}>
          {draft.heightUnit === 'cm' ? (
            <UnitInput
              value={draft.heightCm}
              onChange={(v) => set('heightCm', v)}
              maxLength={HEALTH_LIMITS.heightCm}
              unit="cm"
              invalid={!!errorFor('height')}
              editable={ready}
            />
          ) : (
            <>
              <UnitInput
                value={draft.heightFt}
                onChange={(v) => set('heightFt', v)}
                maxLength={HEALTH_LIMITS.heightFt}
                unit="ft"
                invalid={!!errorFor('height')}
                editable={ready}
              />
              <UnitInput
                value={draft.heightIn}
                onChange={(v) => set('heightIn', v)}
                maxLength={HEALTH_LIMITS.heightIn}
                unit="in"
                invalid={!!errorFor('height')}
                editable={ready}
              />
            </>
          )}
        </View>
        {/* Always on its own line, so it stays in place when ft/in and cm change the number of inputs. */}
        <View style={styles.switchLine}>
          <UnitSwitch
            label="Height unit"
            options={[
              { id: 'ftin', label: 'ft/in' },
              { id: 'cm', label: 'cm' },
            ]}
            value={draft.heightUnit}
            onChange={setHeightUnit}
          />
        </View>
      </Field>

      <Field label="Weight" error={errorFor('weight')}>
        <View style={styles.measureRow}>
          <UnitInput
            value={draft.weight}
            onChange={(v) => set('weight', v)}
            maxLength={HEALTH_LIMITS.weight}
            unit={draft.weightUnit}
            invalid={!!errorFor('weight')}
            editable={ready}
          />
          <UnitSwitch
            label="Weight unit"
            options={[
              { id: 'lb', label: 'lb' },
              { id: 'kg', label: 'kg' },
            ]}
            value={draft.weightUnit}
            onChange={setWeightUnit}
          />
        </View>
      </Field>

      <Field label="Blood type" error={errorFor('bloodType')}>
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

      <Field label="Critical needs" error={errorFor('criticalNeeds')}>
        <View style={styles.chips}>
          {CRITICAL_NEEDS.map((need) => {
            const selected = draft.criticalNeeds.includes(need);
            return (
              <Pressable
                key={need}
                style={[styles.chip, selected && styles.chipSelected]}
                onPress={() => toggleNeed(need)}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: selected }}
              >
                <Text style={styles.chipText}>{need}</Text>
              </Pressable>
            );
          })}
        </View>
      </Field>

      <Field label="Medical conditions" error={errorFor('conditions')}>
        <TextInput
          style={[input('conditions'), styles.multiline]}
          value={draft.conditions}
          onChangeText={(v) => set('conditions', v)}
          maxLength={HEALTH_LIMITS.conditions}
          multiline
          placeholder='e.g. Type 1 diabetes, asthma. Write "None" if none.'
          placeholderTextColor={theme.placeholder}
          editable={ready}
        />
      </Field>

      <Field label="Medications" error={errorFor('medications')}>
        <TextInput
          style={[input('medications'), styles.multiline]}
          value={draft.medications}
          onChangeText={(v) => set('medications', v)}
          maxLength={HEALTH_LIMITS.medications}
          multiline
          placeholder='e.g. Insulin 3x daily. Write "None" if none.'
          placeholderTextColor={theme.placeholder}
          editable={ready}
        />
      </Field>

      <Field label="Allergies" error={errorFor('allergies')}>
        <TextInput
          style={[input('allergies'), styles.multiline]}
          value={draft.allergies}
          onChangeText={(v) => set('allergies', v)}
          maxLength={HEALTH_LIMITS.allergies}
          multiline
          placeholder='e.g. Penicillin, peanuts. Write "None" if none.'
          placeholderTextColor={theme.placeholder}
          editable={ready}
        />
      </Field>

      <Field label="Emergency contact name" error={errorFor('contactName')}>
        <TextInput
          style={input('contactName')}
          value={draft.contactName}
          onChangeText={(v) => set('contactName', v)}
          maxLength={HEALTH_LIMITS.contactName}
          editable={ready}
        />
      </Field>

      <Field label="Emergency contact phone" error={errorFor('contactPhone')}>
        <TextInput
          style={input('contactPhone')}
          value={draft.contactPhone}
          onChangeText={(v) => set('contactPhone', v)}
          maxLength={HEALTH_LIMITS.contactPhone}
          keyboardType="phone-pad"
          autoComplete="tel"
          editable={ready}
        />
      </Field>

      <Field label="Other notes (optional)">
        <TextInput
          style={[styles.input, styles.multiline]}
          value={draft.notes}
          onChangeText={(v) => set('notes', v)}
          maxLength={HEALTH_LIMITS.notes}
          multiline
          placeholder="e.g. Pacemaker, needs refrigerated medicine"
          placeholderTextColor={theme.placeholder}
          editable={ready}
        />
      </Field>

      {message && (
        <Text style={message.kind === 'ok' ? styles.okText : styles.errorText}>{message.text}</Text>
      )}

      <Pressable
        style={[styles.saveBtn, (!ready || saving || (!onboarding && !dirty && !reminderDue)) && styles.disabled]}
        disabled={!ready || saving || (!onboarding && !dirty && !reminderDue)}
        onPress={() => void save()}
        accessibilityRole="button"
      >
        <Text style={styles.saveText}>
          {saving
            ? 'Saving…'
            : onboarding
              ? 'Continue'
              : dirty
                ? 'Save health info'
                : reminderDue
                  ? 'Mark as up to date'
                  : 'Saved'}
        </Text>
      </Pressable>

      {!onboarding && onClear && (
        <Pressable style={styles.clearBtn} onPress={confirmClear} disabled={!ready} accessibilityRole="button">
          <Text style={styles.clearText}>Clear health info</Text>
        </Pressable>
      )}
    </ScrollView>
  );
}

function Field({ label, error, children }: { label: string; error?: string; children: ReactNode }): JSX.Element {
  const styles = useThemedStyles(baseStyles);
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      {children}
      {error && <Text style={styles.fieldError}>{error}</Text>}
    </View>
  );
}

function UnitSwitch<T extends string>({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { id: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}): JSX.Element {
  const styles = useThemedStyles(baseStyles);
  return (
    <View style={styles.segment} accessibilityRole="radiogroup" accessibilityLabel={label}>
      {options.map((option) => {
        const selected = option.id === value;
        return (
          <Pressable
            key={option.id}
            style={[styles.segmentItem, selected && styles.segmentSelected]}
            onPress={() => onChange(option.id)}
            accessibilityRole="radio"
            accessibilityState={{ checked: selected }}
            accessibilityLabel={`${label}: ${option.label}`}
          >
            <Text style={[styles.segmentText, selected && styles.segmentTextSelected]}>{option.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function UnitInput({
  value,
  onChange,
  maxLength,
  unit,
  invalid,
  editable,
}: {
  value: string;
  onChange: (value: string) => void;
  maxLength: number;
  unit: string;
  invalid: boolean;
  editable: boolean;
}): JSX.Element {
  const styles = useThemedStyles(baseStyles);
  return (
    <View style={styles.unitWrap}>
      <TextInput
        style={[styles.input, styles.unitInput, invalid && styles.inputError]}
        value={value}
        onChangeText={(v) => onChange(v.replace(/\D/g, ''))}
        keyboardType="number-pad"
        maxLength={maxLength}
        editable={editable}
        accessibilityLabel={unit}
      />
      <Text style={styles.unitLabel}>{unit}</Text>
    </View>
  );
}

const baseStyles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f8fafc' },
  content: { padding: 20, gap: 18, paddingBottom: 40 },
  headerBlock: { gap: 6 },
  title: { fontSize: 30, fontWeight: '800', color: '#0f172a' },
  subtitle: { fontSize: 16, color: '#475569', lineHeight: 22 },
  emergency: { fontSize: 14, color: '#b91c1c', fontWeight: '600', lineHeight: 20 },
  field: { gap: 8 },
  label: { fontSize: 16, fontWeight: '700', color: '#0f172a' },
  fieldError: { color: '#b91c1c', fontSize: 13 },
  input: { borderWidth: 1, borderColor: '#cbd5e1', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, color: '#0f172a', backgroundColor: 'white' },
  inputError: { borderColor: '#dc2626', borderWidth: 2 },
  short: { width: 100 },
  multiline: { minHeight: 72, textAlignVertical: 'top' },
  unitWrap: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  unitInput: { width: 90 },
  unitLabel: { fontSize: 16, color: '#475569', fontWeight: '600' },
  // Inputs and the unit switch share a line, wrapping onto the next one at large text sizes.
  measureRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12 },
  switchLine: { flexDirection: 'row' },
  segment: { flexDirection: 'row', borderRadius: 10, borderWidth: 1, borderColor: '#cbd5e1', overflow: 'hidden' },
  segmentItem: { paddingVertical: 12, paddingHorizontal: 14, backgroundColor: 'white' },
  segmentSelected: { backgroundColor: '#0f172a' },
  segmentText: { fontSize: 15, fontWeight: '600', color: '#0f172a' },
  segmentTextSelected: { color: 'white' },
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
