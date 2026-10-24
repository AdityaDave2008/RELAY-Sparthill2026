import { useCallback, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MAX_BODY_LENGTH } from '@relay/core';

import { formatRequestBody, type Need } from './contract';

export const BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'] as const;
export type BloodType = (typeof BLOOD_TYPES)[number];

export const CRITICAL_NEEDS = [
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

export interface HealthProfile {
  fullName: string;
  age: string;
  bloodType: BloodType | null;
  criticalNeeds: CriticalNeed[];
  conditions: string;
  medications: string;
  allergies: string;
  contactName: string;
  contactPhone: string;
  notes: string;
}

/** Per-field input limits; also enforced when reading saved data. */
export const HEALTH_LIMITS = {
  fullName: 80,
  age: 3,
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
  bloodType: null,
  criticalNeeds: [],
  conditions: '',
  medications: '',
  allergies: '',
  contactName: '',
  contactPhone: '',
  notes: '',
};

const HEALTH_KEY = 'relay:health-profile:v1';

function text(value: unknown, limit: number): string {
  return typeof value === 'string' ? value.slice(0, limit) : '';
}

/** Treats stored data as untrusted: unknown fields are dropped, lengths capped. */
function sanitize(value: unknown): HealthProfile {
  if (!value || typeof value !== 'object') return EMPTY_HEALTH;
  const v = value as Record<string, unknown>;
  return {
    fullName: text(v.fullName, HEALTH_LIMITS.fullName),
    age: text(v.age, HEALTH_LIMITS.age).replace(/\D/g, ''),
    bloodType: BLOOD_TYPES.includes(v.bloodType as BloodType) ? (v.bloodType as BloodType) : null,
    criticalNeeds: Array.isArray(v.criticalNeeds)
      ? CRITICAL_NEEDS.filter((need) => (v.criticalNeeds as unknown[]).includes(need))
      : [],
    conditions: text(v.conditions, HEALTH_LIMITS.conditions),
    medications: text(v.medications, HEALTH_LIMITS.medications),
    allergies: text(v.allergies, HEALTH_LIMITS.allergies),
    contactName: text(v.contactName, HEALTH_LIMITS.contactName),
    contactPhone: text(v.contactPhone, HEALTH_LIMITS.contactPhone),
    notes: text(v.notes, HEALTH_LIMITS.notes),
  };
}

/** One-line summary for dispatch, or null when nothing has been filled in. */
export function summarizeHealth(profile: HealthProfile): string | null {
  const parts = [
    profile.fullName.trim() && `Name: ${profile.fullName.trim()}`,
    profile.age && `Age: ${profile.age}`,
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
