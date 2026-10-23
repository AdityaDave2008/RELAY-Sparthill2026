// Fictional demo geography (frontend-owned per services/api/README.md).
// A zone id is used as the warning's incidentId.
import type { Zone } from './contract.ts';

export const ZONES: Zone[] = [
  { id: 'north-hills', name: 'North Hills', population: 640, connectivity: 'offline', reach: { digital: 0.55, radio: 0.3, none: 0.15 }, x: 30, y: 24 },
  { id: 'riverside', name: 'Riverside', population: 820, connectivity: 'degraded', reach: { digital: 0.7, radio: 0.2, none: 0.1 }, x: 64, y: 40 },
  { id: 'old-mill', name: 'Old Mill', population: 410, connectivity: 'offline', reach: { digital: 0.35, radio: 0.4, none: 0.25 }, x: 24, y: 68 },
  { id: 'downtown', name: 'Downtown', population: 1500, connectivity: 'online', reach: { digital: 0.9, radio: 0.08, none: 0.02 }, x: 72, y: 76 },
];

export const zoneName = (id: string | undefined) => ZONES.find((z) => z.id === id)?.name ?? id ?? 'All areas';
