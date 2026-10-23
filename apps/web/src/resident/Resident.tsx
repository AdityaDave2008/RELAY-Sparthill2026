import { useEffect, useState } from 'react';
import type { GeoPoint } from '@relay/core';
import { api } from '../api/index.ts';
import { ZONES } from '../zones.ts';
import {
  DELIVERY_STATES,
  LANG_LABEL,
  parseRequestBody,
  type DeliveryState,
  type Lang,
  type Need,
  type WireMessage,
} from '../contract.ts';
import { device, useDevice } from '../device/device.ts';
import { clock, TopBar, timeAgo, Toast, useNow, useToast } from '../ui/common.tsx';
import { Icon, NEED_LABEL } from '../ui/icons.tsx';

const STATE_LABEL: Record<DeliveryState, string> = {
  saved: 'Saved on phone',
  relayed: 'Passed to nearby phone',
  uploaded: 'Reached coordinators',
  acknowledged: 'Reply received',
};

export function Resident({ path }: { path: string[] }) {
  const d = useDevice();
  const tab = path[0] ?? 'inbox';
  const unseen = d.warnings().filter((w) => !d.isSeen(w.id)).length + d.mine().filter((m) => d.ackFor(m.id) && !d.isSeen(d.ackFor(m.id)!.id)).length;

  useEffect(() => {
    void device.syncNow();
  }, []);

  return (
    <>
      <TopBar role="Resident">
        <ConnectionPill />
      </TopBar>
      <main className="page narrow">
        {tab === 'inbox' && <Inbox />}
        {tab === 'new' && <NewRequest />}
        {tab === 'requests' && <MyRequests />}
      </main>
      <nav className="tabbar" aria-label="Resident">
        <a href="#/resident" aria-current={tab === 'inbox' ? 'page' : undefined}>
          <Icon name="bell" />
          <span>
            Inbox {unseen > 0 && <span className="count">{unseen}</span>}
          </span>
        </a>
        <a href="#/resident/new" aria-current={tab === 'new' ? 'page' : undefined}>
          <Icon name="plus" />
          Ask for help
        </a>
        <a href="#/resident/requests" aria-current={tab === 'requests' ? 'page' : undefined}>
          <Icon name="list" />
          My requests
        </a>
      </nav>
    </>
  );
}

function ConnectionPill() {
  const d = useDevice();
  const pending = d.pendingCount();
  if (!d.sync.online) return <span className="badge danger">Offline{pending ? ` · ${pending} waiting` : ''}</span>;
  if (d.sync.syncing) return <span className="badge info">Syncing…</span>;
  if (d.sync.lastError) return <span className="badge warn">Can't reach server · retrying</span>;
  return <span className="badge ok">Online</span>;
}

function StatusBanner() {
  const d = useDevice();
  const now = useNow();
  if (d.sync.online && !d.sync.lastError) {
    return d.sync.lastSuccess ? <p className="small muted">Updated {timeAgo(d.sync.lastSuccess, now)}</p> : null;
  }
  return (
    <div className="banner offline" role="status">
      <Icon name="phone" size={20} />
      <span>
        <strong>No connection.</strong> RELAY still works. New alerts arrive from nearby RELAY phones, and your requests are saved
        and sent as soon as any connection or nearby phone is available.
      </span>
    </div>
  );
}

function localized(m: WireMessage, lang: Lang): { title: string; body: string } {
  const t = m.translations?.[lang];
  return t ?? { title: m.title ?? 'Emergency update', body: m.body };
}

function Inbox() {
  const d = useDevice();
  const now = useNow();
  const warnings = d.warnings();
  const replies = d
    .mine()
    .map((m) => ({ request: m, ack: d.ackFor(m.id) }))
    .filter((x): x is { request: WireMessage; ack: WireMessage } => !!x.ack);
  const zone = ZONES.find((z) => z.id === d.zoneId);

  useEffect(() => {
    const t = setTimeout(() => d.markSeen([...warnings.map((w) => w.id), ...replies.map((r) => r.ack.id)]), 1500);
    return () => clearTimeout(t);
  });

  return (
    <div className="stack-lg">
      <StatusBanner />
      <div className="row between">
        <div>
          <h1>Alerts</h1>
          <p className="muted small">{zone?.name ?? d.zoneId}</p>
        </div>
        <Prefs />
      </div>

      {replies.length > 0 && (
        <section className="stack">
          <div className="section-title">
            <h2>Replies to your requests</h2>
          </div>
          {replies.map(({ request, ack }) => (
            <article key={ack.id} className={`card alert-card info${d.isSeen(ack.id) ? '' : ' unseen'}`}>
              <div className="stack">
                <div className="row between">
                  <span className="badge ok">
                    <Icon name="check" size={14} /> Coordinator reply
                  </span>
                  <span className="small muted">{timeAgo(ack.createdAt, now)}</span>
                </div>
                <p style={{ fontSize: '1.05rem' }}>{ack.body}</p>
                <a className="small" href={`#/resident/requests/${request.id}`}>
                  About your request from {clock(request.createdAt)}
                </a>
              </div>
            </article>
          ))}
        </section>
      )}

      <section className="stack">
        <div className="section-title">
          <h2>Official warnings</h2>
        </div>
        {warnings.length === 0 && (
          <div className="card flat">
            <p className="muted">No warnings for your area yet. They will appear here even without a connection when a nearby RELAY phone has them.</p>
          </div>
        )}
        {warnings.map((w) => {
          const t = localized(w, d.lang);
          return (
            <article key={w.id} className={`card alert-card${d.isSeen(w.id) ? '' : ' unseen'}`}>
              <div className="stack">
                <div className="row between">
                  <span className="badge danger">
                    <Icon name="danger" size={14} /> Warning
                  </span>
                  <span className="badge sim" title="Approval is simulated in this demo; signatures are not implemented yet">
                    Coordinators · simulated approval
                  </span>
                </div>
                <h2>{t.title}</h2>
                <p>{t.body}</p>
                <div className="alert-meta">
                  <span>Issued {clock(w.createdAt)}</span>
                  <span>Expires {clock(w.expiresAt)}</span>
                  <span>{w.hops === 0 ? 'Received directly' : `Passed through ${w.hops} phone${w.hops > 1 ? 's' : ''}`}</span>
                </div>
              </div>
            </article>
          );
        })}
      </section>
    </div>
  );
}

function Prefs() {
  const d = useDevice();
  return (
    <div className="row">
      <select aria-label="Language" value={d.lang} onChange={(e) => d.setPrefs({ lang: e.target.value as Lang })} style={{ width: 'auto' }}>
        {(Object.keys(LANG_LABEL) as Lang[]).map((l) => (
          <option key={l} value={l}>
            {LANG_LABEL[l]}
          </option>
        ))}
      </select>
      <select aria-label="Your area" value={d.zoneId} onChange={(e) => d.setPrefs({ zoneId: e.target.value })} style={{ width: 'auto' }}>
        {ZONES.map((z) => (
          <option key={z.id} value={z.id}>
            {z.name}
          </option>
        ))}
      </select>
    </div>
  );
}

type Gps =
  | { status: 'idle' | 'locating' }
  | { status: 'fixed'; point: GeoPoint }
  | { status: 'error'; message: string };

function useGps(): [Gps, () => void] {
  const [gps, setGps] = useState<Gps>({ status: 'idle' });
  const [watch, setWatch] = useState(0);
  useEffect(() => {
    if (!watch) return;
    if (!('geolocation' in navigator)) {
      setGps({ status: 'error', message: 'This device has no location service.' });
      return;
    }
    if (!window.isSecureContext) {
      setGps({ status: 'error', message: 'Location needs a secure (https) page.' });
      return;
    }
    setGps((g) => (g.status === 'fixed' ? g : { status: 'locating' }));
    const id = navigator.geolocation.watchPosition(
      (p) => setGps({ status: 'fixed', point: { lat: p.coords.latitude, lon: p.coords.longitude, accuracyM: Math.round(p.coords.accuracy) } }),
      (e) =>
        setGps({
          status: 'error',
          message: e.code === e.PERMISSION_DENIED ? 'Location permission was denied.' : 'Could not get a location fix.',
        }),
      { enableHighAccuracy: true, timeout: 30_000, maximumAge: 10_000 },
    );
    return () => navigator.geolocation.clearWatch(id);
  }, [watch]);
  return [gps, () => setWatch((n) => n + 1)];
}

function accuracyLabel(m: number): { label: string; color: string; pct: number } {
  if (m <= 20) return { label: 'Precise', color: 'var(--ok)', pct: 100 };
  if (m <= 100) return { label: 'Approximate', color: '#ca8a04', pct: 60 };
  return { label: 'Rough. Please describe where you are', color: 'var(--danger)', pct: 25 };
}

const NEEDS: Need[] = ['water', 'food', 'medical', 'shelter', 'evacuation', 'power'];

function NewRequest() {
  const d = useDevice();
  const [needs, setNeeds] = useState<Need[]>([]);
  const [people, setPeople] = useState<number | null>(1);
  const [notes, setNotes] = useState('');
  const [gps, locate] = useGps();
  const [toast, showToast] = useToast();

  useEffect(locate, []); // ask for a fix as soon as the form opens

  const toggle = (n: Need) => setNeeds((cur) => (cur.includes(n) ? cur.filter((x) => x !== n) : [...cur, n]));
  const canSend = needs.length > 0 || notes.trim().length > 0;

  function send() {
    const m = d.createHelpRequest({
      needs,
      people,
      notes,
      location: gps.status === 'fixed' ? gps.point : undefined,
    });
    showToast(d.sync.online ? 'Sending…' : 'Saved. It will be sent when a connection or nearby phone is available.');
    setNeeds([]);
    setNotes('');
    setTimeout(() => (location.hash = `#/resident/requests/${m.id}`), 900);
  }

  return (
    <div className="stack-lg">
      <StatusBanner />
      <div>
        <h1>Ask for help</h1>
        <p className="muted">Works without signal. Your request is saved on this phone and passed along until it reaches coordinators.</p>
      </div>

      <section className="stack">
        <h2>What do you need?</h2>
        <div className="chips">
          {NEEDS.map((n) => (
            <button key={n} type="button" className="chip" aria-pressed={needs.includes(n)} onClick={() => toggle(n)}>
              <Icon name={n} />
              {NEED_LABEL[n]}
            </button>
          ))}
        </div>
      </section>

      <section className="stack">
        <h2>How many people?</h2>
        <div className="row">
          <button type="button" className="btn" aria-label="Fewer people" onClick={() => setPeople((p) => Math.max(1, (p ?? 1) - 1))}>
            −
          </button>
          <input
            type="number"
            inputMode="numeric"
            min={1}
            aria-label="Number of people"
            value={people ?? ''}
            onChange={(e) => setPeople(e.target.value ? Math.max(1, Number(e.target.value)) : null)}
            style={{ width: 96, textAlign: 'center' }}
          />
          <button type="button" className="btn" aria-label="More people" onClick={() => setPeople((p) => (p ?? 0) + 1)}>
            +
          </button>
        </div>
      </section>

      <label className="field">
        Tell us more
        <textarea
          value={notes}
          maxLength={700}
          placeholder="e.g. 25 people at the church on Elm St. Running out of drinking water. One person needs insulin."
          onChange={(e) => setNotes(e.target.value)}
        />
      </label>

      <section className="stack">
        <h2>Your location</h2>
        <GpsBlock gps={gps} onRetry={locate} />
      </section>

      <button type="button" className="btn primary lg block" disabled={!canSend} onClick={send}>
        Send request
      </button>
      <p className="small muted">For life-threatening emergencies, call your local emergency number if you can.</p>
      <Toast msg={toast} />
    </div>
  );
}

function GpsBlock({ gps, onRetry }: { gps: Gps; onRetry: () => void }) {
  if (gps.status === 'fixed') {
    const a = accuracyLabel(gps.point.accuracyM ?? 999);
    return (
      <div className="gps">
        <Icon name="pin" size={22} />
        <div style={{ flex: 1 }} className="stack">
          <div className="row between">
            <strong>{a.label}</strong>
            <span className="small muted">±{gps.point.accuracyM} m</span>
          </div>
          <div className="meter" aria-hidden>
            <span style={{ width: `${a.pct}%`, background: a.color }} />
          </div>
        </div>
      </div>
    );
  }
  return (
    <div className="gps">
      <Icon name="pin" size={22} />
      <span style={{ flex: 1 }} className="small">
        {gps.status === 'error' ? `${gps.message} Describe where you are in the message instead.` : 'Finding your location… (works without internet)'}
      </span>
      {gps.status === 'error' && (
        <button type="button" className="btn" onClick={onRetry}>
          Retry
        </button>
      )}
    </div>
  );
}

function Timeline({ id }: { id: string }) {
  const d = useDevice();
  const { state, times, peers } = d.delivery(id);
  const reached = DELIVERY_STATES.indexOf(state);
  return (
    <div className="timeline" aria-label={`Delivery status: ${STATE_LABEL[state]}`}>
      {DELIVERY_STATES.map((s, i) => {
        const done = times[s] !== undefined || i < reached;
        return (
          <div key={s} className={`step${done ? ' done' : i === reached + 1 ? ' current' : ''}`}>
            <span className="dot" />
            <span>{s === 'relayed' && peers > 1 ? `Passed to ${peers} phones` : STATE_LABEL[s]}</span>
            <span className="muted">{times[s] ? clock(times[s]!) : done ? '✓' : ''}</span>
          </div>
        );
      })}
    </div>
  );
}

function MyRequests() {
  const d = useDevice();
  const now = useNow();
  const mine = d.mine();
  const selected = location.hash.split('/')[3];

  return (
    <div className="stack-lg">
      <StatusBanner />
      <div>
        <h1>My requests</h1>
        <p className="muted small">Each request moves through four steps. Nearby RELAY phones carry it for you while you're offline.</p>
      </div>
      {mine.length === 0 && (
        <div className="card flat stack">
          <p className="muted">You haven't sent any requests.</p>
          <a className="btn primary" href="#/resident/new">
            Ask for help
          </a>
        </div>
      )}
      {mine.map((m) => {
        const parsed = parseRequestBody(m.body);
        const ack = d.ackFor(m.id);
        return (
          <article key={m.id} className="card stack" style={selected === m.id ? { borderColor: 'var(--signal)' } : undefined}>
            <div className="row between">
              <div className="row">
                {parsed.needs.map((n) => (
                  <span key={n} className="badge neutral">
                    {NEED_LABEL[n]}
                  </span>
                ))}
                {parsed.people && <span className="badge neutral">{parsed.people} people</span>}
              </div>
              <span className="small muted">{timeAgo(m.createdAt, now)}</span>
            </div>
            {parsed.notes && <p>{parsed.notes}</p>}
            <Timeline id={m.id} />
            {ack && (
              <div className="banner" style={{ background: 'var(--ok-soft)', color: '#064e3b' }}>
                <Icon name="check" size={18} />
                <span>
                  <strong>Coordinator:</strong> {ack.body}
                </span>
              </div>
            )}
          </article>
        );
      })}
      <NearbyTransfer />
    </div>
  );
}

// Where the offline transport (QR / nearby, built by Codex) plugs in.
function NearbyTransfer() {
  const d = useDevice();
  const [toast, showToast] = useToast();
  const waiting = d.mine().filter((m) => d.delivery(m.id).state === 'saved');
  return (
    <section className="card flat stack">
      <h2>Share with a nearby phone</h2>
      <p className="small muted">
        Hold two phones together to pass alerts and requests along without signal. Transfer is handled by the RELAY transport
        module.
      </p>
      {api.mode === 'mock' && (
        <div className="stack">
          <span className="badge sim" style={{ justifySelf: 'start' }}>
            DEMO CONTROL
          </span>
          <button
            type="button"
            className="btn"
            disabled={waiting.length === 0}
            onClick={() => {
              d.recordRelay(
                waiting.map((m) => m.id),
                'demo-volunteer-phone',
              );
              showToast(`Marked ${waiting.length} request(s) as relayed`);
            }}
          >
            Simulate hand-off to a volunteer's phone
          </button>
        </div>
      )}
      <Toast msg={toast} />
    </section>
  );
}
