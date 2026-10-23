// Pictograms are drawn to read without words: they are used on printed
// notices and help cards for residents who may not read the language.
import type { Need, Pictogram } from '../contract.ts';

type IconName = Pictogram | Need | 'bell' | 'plus' | 'list' | 'radio' | 'phone' | 'paper' | 'map' | 'check' | 'people' | 'pin' | 'sparkle';

const PATHS: Record<IconName, JSX.Element> = {
  water: <path d="M12 3c3.5 4.5 6 7.6 6 11a6 6 0 0 1-12 0c0-3.4 2.5-6.5 6-11Z" fill="#0284c7" />,
  food: (
    <g fill="none" stroke="#b45309" strokeWidth="2" strokeLinecap="round">
      <path d="M4 12h16a8 8 0 0 1-16 0Z" fill="#fde68a" />
      <path d="M9 4c0 2 2 2 2 4M14 4c0 2 2 2 2 4" />
    </g>
  ),
  medical: (
    <g>
      <rect x="3" y="3" width="18" height="18" rx="4" fill="#dc2626" />
      <path d="M10 7h4v3h3v4h-3v3h-4v-3H7v-4h3Z" fill="white" />
    </g>
  ),
  shelter: <path d="M3 11 12 4l9 7v9h-6v-5H9v5H3Z" fill="#15803d" />,
  danger: (
    <g>
      <path d="M12 3 22 20H2Z" fill="#facc15" stroke="#000" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M12 9v5M12 16.5v.5" stroke="#000" strokeWidth="2.4" strokeLinecap="round" />
    </g>
  ),
  route: (
    <g fill="none" stroke="#1d4ed8" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="6" cy="18" r="2.5" fill="#1d4ed8" />
      <path d="M8.5 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h9" />
      <path d="m15 3 3 3-3 3" />
    </g>
  ),
  info: (
    <g>
      <circle cx="12" cy="12" r="10" fill="#1d4ed8" />
      <path d="M12 11v6M12 7.5v.5" stroke="white" strokeWidth="2.4" strokeLinecap="round" />
    </g>
  ),
  evacuation: (
    <g fill="none" stroke="#15803d" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="13" cy="4.5" r="2" fill="#15803d" />
      <path d="m8 21 3-6 3 3v3M11 15l1-6 4 3h3M12 9 8 11v3" />
    </g>
  ),
  power: <path d="M13 2 4 14h7l-1 8 9-12h-7Z" fill="#ca8a04" />,
  other: (
    <g>
      <circle cx="12" cy="12" r="10" fill="#64748b" />
      <circle cx="7.5" cy="12" r="1.5" fill="white" />
      <circle cx="12" cy="12" r="1.5" fill="white" />
      <circle cx="16.5" cy="12" r="1.5" fill="white" />
    </g>
  ),
  bell: <path d="M12 3a6 6 0 0 0-6 6v4l-2 3h16l-2-3V9a6 6 0 0 0-6-6Zm-2 15a2 2 0 0 0 4 0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />,
  plus: <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />,
  list: <path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />,
  radio: (
    <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round">
      <rect x="3" y="8" width="18" height="12" rx="2" />
      <circle cx="15.5" cy="14" r="3" />
      <path d="M6 12h4M6 16h4M7 8l10-5" strokeLinecap="round" />
    </g>
  ),
  phone: (
    <g fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="6" y="2" width="12" height="20" rx="3" />
      <path d="M11 18h2" strokeLinecap="round" />
    </g>
  ),
  paper: (
    <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round">
      <path d="M6 2h9l4 4v16H6Z" />
      <path d="M9 11h7M9 15h7M9 7h3" strokeLinecap="round" />
    </g>
  ),
  map: <path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Zm0 0v14m6-12v14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />,
  check: <path d="m5 12 5 5 9-10" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />,
  people: (
    <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <circle cx="9" cy="8" r="3" />
      <path d="M3 20a6 6 0 0 1 12 0M16 5a3 3 0 0 1 0 6M21 20a6 6 0 0 0-4-5.6" />
    </g>
  ),
  pin: (
    <g fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M12 21s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12Z" />
      <circle cx="12" cy="9" r="2.5" />
    </g>
  ),
  sparkle: <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8Z M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8Z" fill="currentColor" />,
};

export function Icon({ name, title, size }: { name: IconName; title?: string; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} role={title ? 'img' : undefined} aria-hidden={title ? undefined : true}>
      {title && <title>{title}</title>}
      {PATHS[name]}
    </svg>
  );
}

export const NEED_LABEL: Record<Need, string> = {
  water: 'Water',
  food: 'Food',
  medical: 'Medical',
  shelter: 'Shelter',
  evacuation: 'Evacuation',
  power: 'Power / charging',
  other: 'Other',
};

export const PICTO_LABEL: Record<Pictogram, string> = {
  water: 'Water',
  food: 'Food',
  medical: 'Medical help',
  shelter: 'Shelter',
  danger: 'Danger',
  route: 'Route',
  info: 'Information',
};
