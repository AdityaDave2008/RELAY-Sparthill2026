import {
  createContext,
  type JSX,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type TextSize = 'normal' | 'large' | 'largest';

export const TEXT_SCALE: Record<TextSize, number> = { normal: 1, large: 1.25, largest: 1.5 };

export interface Settings {
  textSize: TextSize;
  highContrast: boolean;
}

const DEFAULT_SETTINGS: Settings = { textSize: 'normal', highContrast: false };
const SETTINGS_KEY = 'relay:settings:v1';

export interface Theme {
  scale: number;
  highContrast: boolean;
  /** Text and icon colour, darkened for high contrast. */
  color: (value: string) => string;
  /** Placeholder colour that stays distinguishable from typed text. */
  placeholder: string;
}

interface SettingsContextValue {
  ready: boolean;
  settings: Settings;
  error: string | null;
  update: (patch: Partial<Settings>) => void;
  theme: Theme;
}

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: { children: ReactNode }): JSX.Element {
  const [ready, setReady] = useState(false);
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    AsyncStorage.getItem(SETTINGS_KEY)
      .then((saved) => {
        if (!active || !saved) return;
        const v = JSON.parse(saved) as Record<string, unknown>;
        setSettings({
          textSize: v.textSize === 'large' || v.textSize === 'largest' ? v.textSize : 'normal',
          highContrast: v.highContrast === true,
        });
      })
      .catch(() => {
        // Unreadable settings fall back to defaults; they are not critical data.
      })
      .finally(() => {
        if (active) setReady(true);
      });
    return () => {
      active = false;
    };
  }, []);

  const update = useCallback((patch: Partial<Settings>) => {
    setSettings((current) => {
      const next = { ...current, ...patch };
      AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(next))
        .then(() => setError(null))
        .catch((saveError) => setError(`Settings were applied but not saved: ${String(saveError)}`));
      return next;
    });
  }, []);

  const theme = useMemo<Theme>(
    () => ({
      scale: TEXT_SCALE[settings.textSize],
      highContrast: settings.highContrast,
      color: (value) => (settings.highContrast ? contrastText(value) : value),
      placeholder: settings.highContrast ? '#4b4b4b' : '#9ca3af',
    }),
    [settings],
  );

  const value = useMemo(
    () => ({ ready, settings, error, update, theme }),
    [ready, settings, error, update, theme],
  );
  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsContextValue {
  const value = useContext(SettingsContext);
  if (!value) throw new Error('useSettings must be used inside SettingsProvider');
  return value;
}

export function useTheme(): Theme {
  return useSettings().theme;
}

type StyleMap = Record<string, object>;

/**
 * Applies the current text size and contrast settings to a screen's base
 * StyleSheet: font sizes scale, and in high contrast mode text turns black,
 * tinted backgrounds turn white, and borders turn black and thicker.
 */
export function useThemedStyles<T extends StyleMap>(base: T): T {
  const theme = useTheme();
  return useMemo(() => {
    if (theme.scale === 1 && !theme.highContrast) return base;
    const out: StyleMap = {};
    for (const [key, style] of Object.entries(base)) {
      out[key] = transform(style as Record<string, unknown>, theme);
    }
    return out as T;
  }, [base, theme]);
}

const BORDER_WIDTHS = ['borderWidth', 'borderTopWidth', 'borderBottomWidth', 'borderLeftWidth', 'borderRightWidth'];
const BORDER_COLORS = ['borderColor', 'borderTopColor', 'borderBottomColor', 'borderLeftColor', 'borderRightColor'];

function transform(style: Record<string, unknown>, theme: Theme): Record<string, unknown> {
  const next = { ...style };
  for (const key of ['fontSize', 'lineHeight']) {
    if (typeof next[key] === 'number') next[key] = Math.round((next[key] as number) * theme.scale);
  }
  if (!theme.highContrast) return next;

  if (typeof next.color === 'string') next.color = contrastText(next.color);
  if (typeof next.backgroundColor === 'string') next.backgroundColor = contrastBackground(next.backgroundColor);
  for (const key of BORDER_COLORS) {
    // Transparent borders are placeholders (e.g. an unselected tab's indicator); keep them hidden.
    if (typeof next[key] === 'string' && next[key] !== 'transparent') next[key] = '#000000';
  }
  for (const key of BORDER_WIDTHS) {
    const width = next[key];
    // Double, capped at 4, so selected (thicker) borders stay distinguishable.
    if (typeof width === 'number' && width > 0) next[key] = Math.min(Math.max(width * 2, 2), 4);
  }
  return next;
}

// ---- colour helpers -------------------------------------------------------

type Rgb = [number, number, number];

function parse(value: string): Rgb | null {
  const v = value.trim().toLowerCase();
  if (v === 'white') return [255, 255, 255];
  if (v === 'black') return [0, 0, 0];
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/.exec(v)?.[1];
  if (!hex) return null;
  const full = hex.length === 3 ? hex.split('').map((c) => c + c).join('') : hex;
  return [0, 2, 4].map((i) => Number.parseInt(full.slice(i, i + 2), 16)) as Rgb;
}

const hex = ([r, g, b]: Rgb) => `#${[r, g, b].map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`;

function luminance([r, g, b]: Rgb): number {
  const ch = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

/** Contrast ratio against white. */
const onWhite = (rgb: Rgb) => 1.05 / (luminance(rgb) + 0.05);
const saturated = ([r, g, b]: Rgb) => Math.max(r, g, b) - Math.min(r, g, b) > 60;

/** Darken a colour until it reaches WCAG AAA (7:1) against white. */
function darkenToAAA(rgb: Rgb): string {
  let c: Rgb = rgb;
  while (onWhite(c) < 7) c = [c[0] * 0.85, c[1] * 0.85, c[2] * 0.85];
  return hex(c);
}

/** Text: white stays white (it sits on dark fills); colours keep their hue but darken; greys become black. */
function contrastText(value: string): string {
  const rgb = parse(value);
  if (!rgb) return value;
  if (luminance(rgb) > 0.9) return '#ffffff';
  return saturated(rgb) ? darkenToAAA(rgb) : '#000000';
}

/** Backgrounds: light tints become white; coloured or dark fills darken so white text on them passes 7:1. */
function contrastBackground(value: string): string {
  const rgb = parse(value);
  if (!rgb) return value;
  if (luminance(rgb) > 0.6) return '#ffffff';
  return saturated(rgb) ? darkenToAAA(rgb) : '#000000';
}
