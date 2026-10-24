import { useCallback, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MAX_BODY_LENGTH } from '@relay/core';

import { formatRequestBody, type Need } from './contract';

export const BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'] as const;
export type BloodType = (typeof BLOOD_TYPES)[number];

/** "None" is exclusive: selecting it clears the others, and vice versa. */
export const NO_CRITICAL_NEEDS = 'None';
export const CRITICAL_NEEDS = [
  NO_CRITICAL_NEEDS,
  'Insulin-dependent',
  'Needs oxygen',
  'Dialysis',
  'Uses wheelchair',
  'Limited mobility',
  'Pregnant',
  'Hearing impaired',
  'Vision impaired',
] as const;
export type CriticalNeed = (typeof CRITICAL_NEEDS)[number];

export type HeightUnit = 'ftin' | 'cm';
export type WeightUnit = 'lb' | 'kg';

export interface HealthProfile {
  fullName: string;
  age: string;
  /** Height is entered in ft + in or in cm; weight in lb or kg. Chosen separately. */
  heightUnit: HeightUnit;
  weightUnit: WeightUnit;
  heightCm: string;
  heightFt: string;
  heightIn: string;
  weight: string;
  bloodType: BloodType | null;
  criticalNeeds: CriticalNeed[];
  conditions: string;
  medications: string;
  allergies: string;
  contactName: string;
  contactPhone: string;
  /** The only optional field. */
  notes: string;
}

/** Per-field input limits; also enforced when reading saved data. */
export const HEALTH_LIMITS = {
  fullName: 80,
  age: 3,
  heightCm: 3,
  heightFt: 1,
  heightIn: 2,
  weight: 3,
  conditions: 200,
  medications: 200,
  allergies: 200,
  contactName: 80,
  contactPhone: 30,
  notes: 200,
} as const;

export const EMPTY_HEALTH: HealthProfile = {
  fullName: '',
  age: '',
  heightUnit: 'ftin',
  weightUnit: 'lb',
  heightCm: '',
  heightFt: '',
  heightIn: '',
  weight: '',
  bloodType: null,
  criticalNeeds: [],
  conditions: '',
  medications: '',
  allergies: '',
  contactName: '',
  contactPhone: '',
  notes: '',
};

export type HealthField =
  | 'fullName'
  | 'age'
  | 'height'
  | 'weight'
  | 'bloodType'
  | 'criticalNeeds'
  | 'conditions'
  | 'medications'
  | 'allergies'
  | 'contactName'
  | 'contactPhone';

const HEALTH_KEY = 'relay:health-profile:v1';

function text(value: unknown, limit: number): string {
  return typeof value === 'string' ? value.slice(0, limit) : '';
}

function digits(value: unknown, limit: number): string {
  return text(value, 10).replace(/\D/g, '').slice(0, limit);
}

/** Integer in [min, max], or null for blank / non-numeric / out-of-range input. */
function intIn(value: string, min: number, max: number): number | null {
  if (!/^\d+$/.test(value)) return null;
  const n = Number.parseInt(value, 10);
  return n >= min && n <= max ? n : null;
}

/** Treats stored data as untrusted: unknown fields are dropped, lengths capped. */
function sanitize(value: unknown): HealthProfile {
  if (!value || typeof value !== 'object') return EMPTY_HEALTH;
  const v = value as Record<string, unknown>;
  const needs = Array.isArray(v.criticalNeeds)
    ? CRITICAL_NEEDS.filter((need) => (v.criticalNeeds as unknown[]).includes(need))
    : [];
  return {
    fullName: text(v.fullName, HEALTH_LIMITS.fullName),
    age: digits(v.age, HEALTH_LIMITS.age),
    // Profiles saved before the split stored one shared `units` value.
    heightUnit: v.heightUnit === 'cm' || (v.heightUnit === undefined && v.units === 'metric') ? 'cm' : 'ftin',
    weightUnit: v.weightUnit === 'kg' || (v.weightUnit === undefined && v.units === 'metric') ? 'kg' : 'lb',
    heightCm: digits(v.heightCm, HEALTH_LIMITS.heightCm),
    heightFt: digits(v.heightFt, HEALTH_LIMITS.heightFt),
    heightIn: digits(v.heightIn, HEALTH_LIMITS.heightIn),
    weight: digits(v.weight, HEALTH_LIMITS.weight),
    bloodType: BLOOD_TYPES.includes(v.bloodType as BloodType) ? (v.bloodType as BloodType) : null,
    criticalNeeds: needs.includes(NO_CRITICAL_NEEDS) && needs.length > 1 ? [NO_CRITICAL_NEEDS] : needs,
    conditions: text(v.conditions, HEALTH_LIMITS.conditions),
    medications: text(v.medications, HEALTH_LIMITS.medications),
    allergies: text(v.allergies, HEALTH_LIMITS.allergies),
    contactName: text(v.contactName, HEALTH_LIMITS.contactName),
    contactPhone: text(v.contactPhone, HEALTH_LIMITS.contactPhone),
    notes: text(v.notes, HEALTH_LIMITS.notes),
  };
}

/** Field-level problems; an empty object means the profile is complete. */
export function validateHealth(p: HealthProfile): Partial<Record<HealthField, string>> {
  const errors: Partial<Record<HealthField, string>> = {};
  const required = 'Required';
  const none = 'Required. Write "None" if this does not apply.';

  if (!p.fullName.trim()) errors.fullName = required;
  if (intIn(p.age, 0, 120) === null) errors.age = p.age ? 'Enter an age from 0 to 120' : required;

  if (p.heightUnit === 'cm') {
    if (intIn(p.heightCm, 30, 250) === null) {
      errors.height = p.heightCm ? 'Enter a height from 30 to 250 cm' : required;
    }
  } else {
    const ft = intIn(p.heightFt, 1, 8);
    const inches = p.heightIn === '' ? 0 : intIn(p.heightIn, 0, 11);
    if (ft === null || inches === null) {
      errors.height = p.heightFt ? 'Enter feet from 1 to 8 and inches from 0 to 11' : required;
    }
  }
  if (p.weightUnit === 'kg') {
    if (intIn(p.weight, 1, 350) === null) {
      errors.weight = p.weight ? 'Enter a weight from 1 to 350 kg' : required;
    }
  } else if (intIn(p.weight, 2, 770) === null) {
    errors.weight = p.weight ? 'Enter a weight from 2 to 770 lb' : required;
  }

  if (!p.bloodType) errors.bloodType = 'Required. Choose "Unknown" if you are not sure.';
  if (p.criticalNeeds.length === 0) errors.criticalNeeds = 'Required. Choose "None" if none apply.';
  if (!p.conditions.trim()) errors.conditions = none;
  if (!p.medications.trim()) errors.medications = none;
  if (!p.allergies.trim()) errors.allergies = none;
  if (!p.contactName.trim()) errors.contactName = required;
  if (p.contactPhone.replace(/\D/g, '').length < 7) {
    errors.contactPhone = p.contactPhone.trim() ? 'Enter a phone number with at least 7 digits' : required;
  }
  return errors;
}

/** Height fields converted to the other unit; blank stays blank. */
export function convertHeight(
  p: Pick<HealthProfile, 'heightCm' | 'heightFt' | 'heightIn'>,
  to: HeightUnit,
): Pick<HealthProfile, 'heightCm' | 'heightFt' | 'heightIn'> {
  if (to === 'cm') {
    if (!p.heightFt && !p.heightIn) return { heightCm: '', heightFt: '', heightIn: '' };
    const inches = Number(p.heightFt || 0) * 12 + Number(p.heightIn || 0);
    return { heightCm: String(Math.round(inches * 2.54)), heightFt: '', heightIn: '' };
  }
  if (!p.heightCm) return { heightCm: '', heightFt: '', heightIn: '' };
  let ft = Math.floor(Number(p.heightCm) / 2.54 / 12);
  let inches = Math.round(Number(p.heightCm) / 2.54 - ft * 12);
  if (inches === 12) { ft += 1; inches = 0; }
  return { heightCm: '', heightFt: String(ft), heightIn: String(inches) };
}

/** Weight converted to the other unit; blank stays blank. */
export function convertWeight(weight: string, to: WeightUnit): string {
  if (!weight) return '';
  const n = Number(weight);
  return String(Math.round(to === 'kg' ? n * 0.45359237 : n / 0.45359237));
}

export function isHealthComplete(profile: HealthProfile): boolean {
  return Object.keys(validateHealth(profile)).length === 0;
}

function formatHeight(p: HealthProfile): string | null {
  if (p.heightUnit === 'cm') return p.heightCm ? `${p.heightCm} cm` : null;
  if (!p.heightFt) return null;
  return `${p.heightFt} ft ${p.heightIn || '0'} in`;
}

/** One-line summary for dispatch, or null when nothing has been filled in. */
export function summarizeHealth(profile: HealthProfile): string | null {
  const height = formatHeight(profile);
  const parts = [
    profile.fullName.trim() && `Name: ${profile.fullName.trim()}`,
    profile.age && `Age: ${profile.age}`,
    height && `Height: ${height}`,
    profile.weight && `Weight: ${profile.weight} ${profile.weightUnit}`,
    profile.bloodType && `Blood: ${profile.bloodType}`,
    profile.criticalNeeds.length > 0 && `Critical: ${profile.criticalNeeds.join(', ')}`,
    profile.conditions.trim() && `Conditions: ${profile.conditions.trim()}`,
    profile.medications.trim() && `Medications: ${profile.medications.trim()}`,
    profile.allergies.trim() && `Allergies: ${profile.allergies.trim()}`,
    (profile.contactName.trim() || profile.contactPhone.trim()) &&
      `Emergency contact: ${[profile.contactName.trim(), profile.contactPhone.trim()].filter(Boolean).join(' ')}`,
    profile.notes.trim() && `Notes: ${profile.notes.trim()}`,
  ].filter(Boolean) as string[];
  return parts.length ? `HEALTH (shared by resident): ${parts.join(' · ')}` : null;
}

/**
 * Builds the help-request body, appending the health summary after the notes.
 * The summary is shortened if needed so the message stays within the
 * shared 1000-character limit; the resident's own notes are never cut.
 */
export function composeRequestBody(
  needs: Need[],
  people: number | null,
  notes: string,
  health: string | null,
): string {
  const build = (h: string | null) =>
    formatRequestBody(needs, people, [notes.trim(), h].filter(Boolean).join('\n\n'));
  let body = build(health);
  if (health && body.length > MAX_BODY_LENGTH) {
    const keep = Math.max(0, health.length - (body.length - MAX_BODY_LENGTH) - 1);
    body = build(keep > 0 ? `${health.slice(0, keep)}…` : null);
  }
  return body;
}

export function useHealthProfile(): {
  ready: boolean;
  profile: HealthProfile;
  error: string | null;
  save: (next: HealthProfile) => Promise<void>;
  clear: () => Promise<void>;
} {
  const [ready, setReady] = useState(false);
  const [profile, setProfile] = useState<HealthProfile>(EMPTY_HEALTH);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    AsyncStorage.getItem(HEALTH_KEY)
      .then((saved) => {
        if (!active) return;
        if (saved) {
          try {
            setProfile(sanitize(JSON.parse(saved)));
          } catch {
            setError('Saved health info could not be read. Please fill it in again.');
          }
        }
        setReady(true);
      })
      .catch((loadError) => {
        if (!active) return;
        setError(`Could not load health info: ${String(loadError)}`);
        setReady(true);
      });
    return () => {
      active = false;
    };
  }, []);

  const save = useCallback(async (next: HealthProfile) => {
    const clean = sanitize(next);
    await AsyncStorage.setItem(HEALTH_KEY, JSON.stringify(clean));
    setProfile(clean);
    setError(null);
  }, []);

  const clear = useCallback(async () => {
    await AsyncStorage.removeItem(HEALTH_KEY);
    setProfile(EMPTY_HEALTH);
    setError(null);
  }, []);

  return { ready, profile, error, save, clear };
}
