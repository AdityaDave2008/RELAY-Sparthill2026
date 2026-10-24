// Help-request body convention, kept byte-for-byte compatible with the web app
// (apps/web/src/contract.ts) so the coordinator dashboard and API parse mobile
// requests identically.

export type Need = 'water' | 'food' | 'medical' | 'shelter' | 'evacuation' | 'power';

export const NEED_LABEL: Record<Need, string> = {
  water: 'Water',
  food: 'Food',
  medical: 'Medical',
  shelter: 'Shelter',
  evacuation: 'Evacuation',
  power: 'Power / charging',
};

export const NEEDS: Need[] = ['water', 'food', 'medical', 'shelter', 'evacuation', 'power'];

/** Encodes needs + people into the first line, notes on the following lines. */
export function formatRequestBody(needs: Need[], people: number | null, notes: string): string {
  const header = `NEEDS: ${needs.length ? needs.join(', ') : 'unspecified'} | PEOPLE: ${people ?? 'unknown'}`;
  return notes.trim() ? `${header}\n${notes.trim()}` : header;
}
