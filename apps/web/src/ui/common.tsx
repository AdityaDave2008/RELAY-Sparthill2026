import { useEffect, useState, type ReactNode } from 'react';
import { api } from '../api/index.ts';
import { Icon } from './icons.tsx';

export function useRoute(): string[] {
  const read = () => location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);
  const [parts, setParts] = useState(read);
  useEffect(() => {
    const on = () => {
      setParts(read());
      window.scrollTo(0, 0);
    };
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return parts;
}

export function TopBar({ role, children }: { role?: string; children?: ReactNode }) {
  return (
    <header className="topbar">
      <a className="brand" href="#/">
        <img src="/icon.svg" alt="" />
        RELAY
      </a>
      {role && <span className="role">{role}</span>}
      <span className="spacer" />
      {children}
    </header>
  );
}

// Every screen showing the approval workflow carries this label.
export function SimulationBanner({ children }: { children?: ReactNode }) {
  return (
    <div className="banner sim" role="note">
      <strong>SIMULATION</strong>
      <span>
        {children ??
          'The government approval step is simulated for this demo. No real agency or alert system is contacted.'}
      </span>
    </div>
  );
}

export function BedrockHeader({ model }: { model: string }) {
  const mock = api.mode === 'mock' || model.startsWith('mock');
  return (
    <div className={`bedrock-head${mock ? ' mock' : ''}`}>
      <Icon name="sparkle" size={16} />
      {mock ? 'MOCK AI (connect API for Amazon Bedrock)' : 'Amazon Bedrock'}
      <span className="mono muted" style={{ fontWeight: 400 }}>
        {model}
      </span>
    </div>
  );
}

export function timeAgo(ms: number, now: number = Date.now()): string {
  const s = Math.max(0, Math.round((now - ms) / 1000));
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} h ago`;
  return new Date(ms).toLocaleDateString();
}

export function clock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export function useNow(intervalMs = 30_000): number {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(t);
  }, [intervalMs]);
  return now;
}

export function useToast(): [string | null, (msg: string) => void] {
  const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => {
    if (!msg) return;
    const t = setTimeout(() => setMsg(null), 3000);
    return () => clearTimeout(t);
  }, [msg]);
  return [msg, setMsg];
}

export function Toast({ msg }: { msg: string | null }) {
  return msg ? (
    <div className="toast" role="status">
      {msg}
    </div>
  ) : null;
}

export function usePoll<T>(load: () => Promise<T>, intervalMs: number, deps: unknown[] = []): [T | undefined, () => void, string | null] {
  const [data, setData] = useState<T>();
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let alive = true;
    const run = () =>
      load().then(
        (d) => alive && (setData(d), setError(null)),
        (e: unknown) => alive && setError(e instanceof Error ? e.message : String(e)),
      );
    void run();
    const t = setInterval(run, intervalMs);
    // The mock API lives in localStorage: refresh when another tab writes.
    const onStorage = () => void run();
    window.addEventListener('storage', onStorage);
    return () => {
      alive = false;
      clearInterval(t);
      window.removeEventListener('storage', onStorage);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tick, intervalMs, ...deps]);
  return [data, () => setTick((n) => n + 1), error];
}
