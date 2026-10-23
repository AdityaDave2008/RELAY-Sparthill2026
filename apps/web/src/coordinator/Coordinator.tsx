import { useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../api/index.ts';
import { LANG_LABEL, parseRequestBody, type Lang, type RequestRecord, type WarningDraft, type WireMessage, type Zone } from '../contract.ts';
import { BedrockHeader, clock, SimulationBanner, timeAgo, Toast, TopBar, useNow, usePoll, useToast } from '../ui/common.tsx';
import { Icon, PICTO_LABEL } from '../ui/icons.tsx';
import { ZONES, zoneName } from '../zones.ts';

async function loadAllRequests(): Promise<RequestRecord[]> {
  const byId = new Map<string, RequestRecord>();
  let cursor: string | null = null;
  for (let page = 0; page < 20; page++) {
    const res: { requests: RequestRecord[]; nextCursor: string | null } = await api.requests(cursor);
    for (const r of res.requests) byId.set(r.message.id, r);
    cursor = res.nextCursor;
    if (!cursor) break;
  }
  return [...byId.values()].sort((a, b) => b.receivedAt - a.receivedAt);
}

// Replies are kept per browser so the dashboard can show what was answered;
// the API has no "list replies" route yet.
const REPLIED_KEY = 'relay.coordinator.replies.v1';
function loadReplies(): Record<string, { body: string; at: number }> {
  try {
    return JSON.parse(localStorage.getItem(REPLIED_KEY) ?? '{}');
  } catch {
    return {};
  }
}

export function Coordinator() {
  const [requests, refresh, error] = usePoll(loadAllRequests, 5000);
  const [health] = usePoll(() => api.health(), 30_000);
  const [replies, setReplies] = useState(loadReplies);
  const [zoneId, setZoneId] = useState<string | null>(null);
  const [toast, showToast] = useToast();

  const counts = useMemo(() => {
    const c: Record<string, { total: number; open: number }> = {};
    for (const r of requests ?? []) {
      const z = r.message.incidentId ?? 'unknown';
      c[z] ??= { total: 0, open: 0 };
      c[z].total++;
      if (!replies[r.message.id]) c[z].open++;
    }
    return c;
  }, [requests, replies]);

  const visible = (requests ?? []).filter((r) => !zoneId || r.message.incidentId === zoneId);
  const open = visible.filter((r) => !replies[r.message.id]);
  const done = visible.filter((r) => replies[r.message.id]);

  function recordReply(id: string, body: string) {
    const next = { ...replies, [id]: { body, at: Date.now() } };
    setReplies(next);
    try {
      localStorage.setItem(REPLIED_KEY, JSON.stringify(next));
    } catch {
      // not persisted; still shown this session
    }
    showToast('Reply queued for delivery to the resident');
  }

  return (
    <>
      <TopBar role="Coordinator · Riverbend County EOC (fictional)">
        <ApiPill bedrock={health?.bedrockConfigured} />
      </TopBar>
      <main className="page stack-lg">
        <SimulationBanner>
          Demo command center with fictional places and people. Publishing a warning stands in for an official approval, and no real
          alert system is contacted.
        </SimulationBanner>
        <div className="dash">
          <div className="stack-lg">
            <ZoneMap selected={zoneId} onSelect={setZoneId} counts={counts} />
            <WarningComposer zoneId={zoneId ?? ZONES[0].id} onPublished={(w) => showToast(`Warning published to ${zoneName(w.incidentId)}`)} />
          </div>
          <section className="stack">
            <div className="section-title">
              <h2>
                Incoming requests {zoneId && `· ${zoneName(zoneId)}`} ({open.length} open)
              </h2>
              <button type="button" className="btn ghost small" onClick={refresh}>
                Refresh
              </button>
            </div>
            {error && <div className="banner warn">Can't reach the API: {error}. Showing the last data received.</div>}
            {requests && visible.length === 0 && (
              <div className="card flat">
                <p className="muted">No requests yet. They arrive here as soon as any phone carrying them reaches a connection.</p>
              </div>
            )}
            {open.map((r) => (
              <RequestCard key={r.message.id} record={r} onReplied={recordReply} />
            ))}
            {done.length > 0 && (
              <details>
                <summary className="small muted" style={{ cursor: 'pointer', padding: '8px 0' }}>
                  {done.length} answered
                </summary>
                <div className="stack">
                  {done.map((r) => (
                    <RequestCard key={r.message.id} record={r} reply={replies[r.message.id]} onReplied={recordReply} />
                  ))}
                </div>
              </details>
            )}
          </section>
        </div>
      </main>
      <Toast msg={toast} />
    </>
  );
}

function ApiPill({ bedrock }: { bedrock?: boolean }) {
  if (api.mode === 'mock') return <span className="badge warn">Mock API · no Bedrock</span>;
  return <span className={`badge ${bedrock ? 'ok' : 'warn'}`}>{bedrock ? 'Amazon Bedrock connected' : 'Bedrock not configured'}</span>;
}

function ZoneMap({ selected, onSelect, counts }: { selected: string | null; onSelect: (id: string | null) => void; counts: Record<string, { total: number; open: number }> }) {
  const zone = ZONES.find((z) => z.id === selected);
  return (
    <section className="card stack">
      <div className="row between">
        <h2>Incident zones</h2>
        {selected && (
          <button type="button" className="btn ghost small" onClick={() => onSelect(null)}>
            Show all
          </button>
        )}
      </div>
      <div className="map" role="group" aria-label="Map of incident zones">
        <svg viewBox="0 0 100 75" preserveAspectRatio="none" aria-hidden>
          <path d="M0 48 C 20 44, 35 56, 50 50 S 80 34, 100 40 L100 46 C 80 40, 62 56, 50 56 S 22 50, 0 54 Z" fill="#7dd3fc" />
          <path d="M8 0 L 40 75 M 60 0 L 52 75 M 0 30 L 100 22" stroke="#cbd5e1" strokeWidth="0.8" fill="none" />
          <path d="M 42 52 L 47 52" stroke="#b91c1c" strokeWidth="1.6" strokeDasharray="1 1" />
        </svg>
        {ZONES.map((z) => (
          <button
            key={z.id}
            type="button"
            className="zone-pin"
            style={{ left: `${z.x}%`, top: `${z.y}%` }}
            aria-pressed={selected === z.id}
            onClick={() => onSelect(selected === z.id ? null : z.id)}
          >
            <span className={`ring conn-${z.connectivity}`}>{counts[z.id]?.open ?? 0}</span>
            <span className="label">{z.name}</span>
          </button>
        ))}
      </div>
      <div className="legend">
        <span>
          <i className="conn-online" />
          Online
        </span>
        <span>
          <i className="conn-degraded" />
          Degraded
        </span>
        <span>
          <i className="conn-offline" />
          No signal
        </span>
        <span>Number = open requests</span>
      </div>
      {zone && <ZoneDetail zone={zone} />}
    </section>
  );
}

function ZoneDetail({ zone }: { zone: Zone }) {
  const unreachable = Math.round(zone.population * zone.reach.none);
  return (
    <div className="stack" style={{ borderTop: '1px solid var(--line)', paddingTop: 12 }}>
      <div className="row between">
        <h3>{zone.name}</h3>
        <span className="small muted">{zone.population.toLocaleString()} residents (est.)</span>
      </div>
      <div className="reach" aria-hidden>
        <span style={{ width: `${zone.reach.digital * 100}%` }} />
        <span style={{ width: `${zone.reach.radio * 100}%` }} />
        <span style={{ width: `${zone.reach.none * 100}%` }} />
      </div>
      <div className="legend">
        <span>
          <i style={{ background: 'var(--info)' }} />
          Phone {Math.round(zone.reach.digital * 100)}%
        </span>
        <span>
          <i style={{ background: '#f59e0b' }} />
          Radio only {Math.round(zone.reach.radio * 100)}%
        </span>
        <span>
          <i style={{ background: 'var(--danger)' }} />
          No device {Math.round(zone.reach.none * 100)}%
        </span>
      </div>
      {unreachable > 0 && (
        <div className="banner warn">
          <Icon name="paper" size={18} />
          <span>
            About <strong>{unreachable}</strong> residents can't receive digital alerts.{' '}
            <a href={`#/volunteer/${zone.id}`}>Plan paper and spoken delivery →</a>
          </span>
        </div>
      )}
    </div>
  );
}

function RequestCard({ record, reply, onReplied }: { record: RequestRecord; reply?: { body: string; at: number }; onReplied: (id: string, body: string) => void }) {
  const now = useNow();
  const m = record.message;
  const parsed = parseRequestBody(m.body);
  const [classification, setClassification] = useState(record.classification);
  const [busy, setBusy] = useState<'classify' | 'reply' | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [text, setText] = useState('');
  const c = classification ?? record.classification;
  const critical = /medical|evacuation/.test((c?.needs ?? parsed.needs).join(','));
  const fromPaper = m.originDeviceId.startsWith('paper:');

  // Bedrock reads every request as soon as it reaches the dashboard. The
  // button below is only for retrying after a failure.
  const autoClassified = useRef(false);
  useEffect(() => {
    if (c || autoClassified.current) return;
    autoClassified.current = true;
    void classify();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function classify() {
    setBusy('classify');
    setErr(null);
    try {
      setClassification((await api.classify(m.id)).classification);
    } catch (e) {
      setErr(`Bedrock analysis failed: ${e instanceof Error ? e.message : e}. The request is kept; try again.`);
    } finally {
      setBusy(null);
    }
  }

  async function sendReply(body: string) {
    setBusy('reply');
    setErr(null);
    try {
      // Stable id so a retried click doesn't create a second reply.
      await api.reply(m.id, `reply-${m.id}`.slice(0, 64), body);
      onReplied(m.id, body);
      setText('');
    } catch (e) {
      setErr(`Reply not sent: ${e instanceof Error ? e.message : e}`);
    } finally {
      setBusy(null);
    }
  }

  const quick = [
    'Received. Help is being arranged. Stay where you are if it is safe.',
    'Water and supplies are available at the nearest shelter listed in your alerts.',
    'A volunteer team will check on you. Keep your phone with you.',
  ];

  return (
    <article className={`req ${critical ? 'critical' : 'high'}`}>
      <div className="row between">
        <div className="row">
          <strong>{zoneName(m.incidentId)}</strong>
          {fromPaper ? <span className="badge neutral">Paper card</span> : <span className="badge neutral">Phone</span>}
          {m.hops > 0 && <span className="badge info">Relayed through {m.hops} phone{m.hops > 1 ? 's' : ''}</span>}
        </div>
        <span className="small muted" title={new Date(m.createdAt).toLocaleString()}>
          Sent {clock(m.createdAt)} · arrived {timeAgo(record.receivedAt, now)}
        </span>
      </div>
      <p style={{ whiteSpace: 'pre-wrap' }}>{parsed.notes || m.body}</p>
      <div className="row small muted">
        {parsed.needs.length > 0 && <span>Ticked: {parsed.needs.join(', ')}</span>}
        {parsed.people && <span>· {parsed.people} people</span>}
        {m.location && (
          <span>
            · GPS {m.location.lat.toFixed(4)}, {m.location.lon.toFixed(4)}
            {m.location.accuracyM !== undefined && ` (±${m.location.accuracyM} m)`}
          </span>
        )}
      </div>

      {c ? (
        <div className="bedrock">
          <BedrockHeader model={c.modelId} />
          <dl className="kv" style={{ marginTop: 8 }}>
            <dt>Summary</dt>
            <dd>{c.summary}</dd>
            <dt>Needs</dt>
            <dd>{c.needs.length ? c.needs.join(', ') : 'Not stated'}</dd>
            <dt>People</dt>
            <dd>{c.peopleCount ?? 'Unknown'}</dd>
            <dt>Location</dt>
            <dd>{c.locationDescription ?? 'Not described'}</dd>
          </dl>
          <p className="small muted" style={{ marginTop: 6 }}>
            AI output. A person must check it before acting.
          </p>
        </div>
      ) : (
        <button type="button" className="btn" onClick={classify} disabled={busy !== null}>
          <Icon name="sparkle" size={18} />
          {busy === 'classify' ? 'Amazon Bedrock is reading this request…' : api.mode === 'mock' ? 'Analyze (mock AI)' : 'Retry Amazon Bedrock analysis'}
        </button>
      )}

      {err && <div className="banner warn">{err}</div>}

      {reply ? (
        <div className="banner" style={{ background: 'var(--ok-soft)', color: '#064e3b' }}>
          <Icon name="check" size={18} />
          <span>
            Replied {clock(reply.at)}: {reply.body}
          </span>
        </div>
      ) : (
        <div className="stack">
          <div className="chips">
            {quick.map((q) => (
              <button key={q} type="button" className="chip small" style={{ minHeight: 36, fontWeight: 500 }} onClick={() => setText(q)}>
                {q.split('.')[0]}
              </button>
            ))}
          </div>
          <div className="row" style={{ flexWrap: 'nowrap' }}>
            <input type="text" placeholder="Reply to resident…" value={text} maxLength={500} onChange={(e) => setText(e.target.value)} aria-label="Reply" />
            <button type="button" className="btn ok" disabled={!text.trim() || busy !== null} onClick={() => sendReply(text.trim())}>
              {busy === 'reply' ? 'Sending…' : 'Acknowledge'}
            </button>
          </div>
        </div>
      )}
    </article>
  );
}

const LANGS: Lang[] = ['en', 'es', 'vi', 'zh'];

function WarningComposer({ zoneId, onPublished }: { zoneId: string; onPublished: (w: WireMessage) => void }) {
  const [raw, setRaw] = useState('');
  const [target, setTarget] = useState(zoneId);
  const [langs, setLangs] = useState<Lang[]>(['en', 'es']);
  const [draft, setDraft] = useState<WarningDraft | null>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [approver, setApprover] = useState('');
  const [busy, setBusy] = useState<'draft' | 'publish' | null>(null);
  const [err, setErr] = useState<string | null>(null);

  // Follow the zone picked on the map until the coordinator starts a draft.
  if (!draft && !raw && target !== zoneId) setTarget(zoneId);

  async function makeDraft() {
    setBusy('draft');
    setErr(null);
    try {
      const d = await api.draftWarning(raw, target, langs);
      setDraft(d);
      setTitle(d.title);
      setBody(d.body);
    } catch (e) {
      setErr(`Bedrock drafting is unavailable (${e instanceof Error ? e.message : e}). You can still write the warning yourself below.`);
      setDraft({ title: '', body: raw, noticeLines: [], translations: {}, pictograms: ['info'], radioScript: '', uncertain: [], source: 'mock', modelId: 'none' });
      setTitle(raw.split(/[.!?]/)[0]?.slice(0, 80) ?? '');
      setBody(raw);
    } finally {
      setBusy(null);
    }
  }

  async function publish() {
    if (!draft) return;
    setBusy('publish');
    setErr(null);
    try {
      const w = await api.publishWarning({
        id: crypto.randomUUID(),
        body: body.trim(),
        incidentId: target,
        title: title.trim(),
        translations: draft.translations,
        ttlMs: 12 * 60 * 60 * 1000,
      });
      try {
        localStorage.setItem(`relay.notice.${target}`, JSON.stringify({ ...draft, title, body, publishedAt: w.createdAt, id: w.id }));
      } catch {
        // print view falls back to the latest warning on the device
      }
      onPublished(w);
      setDraft(null);
      setRaw('');
      setApprover('');
    } catch (e) {
      setErr(`Not published: ${e instanceof Error ? e.message : e}`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="card stack">
      <h2>Public warning</h2>
      {!draft ? (
        <>
          <label className="field">
            Field report (paste raw notes)
            <textarea
              value={raw}
              onChange={(e) => setRaw(e.target.value)}
              placeholder="e.g. Shelter at Lincoln Middle School gym open, has water + cots. Clinic on 3rd closed. Bridge on Mill Rd flooded, use Route 9. Insulin may be available at shelter, unconfirmed."
            />
          </label>
          <label className="field">
            Send to
            <select value={target} onChange={(e) => setTarget(e.target.value)}>
              {ZONES.map((z) => (
                <option key={z.id} value={z.id}>
                  {z.name}
                </option>
              ))}
            </select>
          </label>
          <div className="stack">
            <span className="small" style={{ fontWeight: 600 }}>
              Languages
            </span>
            <div className="chips">
              {LANGS.map((l) => (
                <button
                  key={l}
                  type="button"
                  className="chip"
                  aria-pressed={langs.includes(l)}
                  disabled={l === 'en'}
                  onClick={() => setLangs((cur) => (cur.includes(l) ? cur.filter((x) => x !== l) : [...cur, l]))}
                >
                  {LANG_LABEL[l]}
                </button>
              ))}
            </div>
          </div>
          <button type="button" className="btn dark" disabled={raw.trim().length < 10 || busy !== null} onClick={makeDraft}>
            <Icon name="sparkle" size={18} />
            {busy === 'draft' ? 'Drafting…' : api.mode === 'mock' ? 'Draft with mock AI' : 'Draft with Amazon Bedrock'}
          </button>
        </>
      ) : (
        <>
          {draft.modelId !== 'none' && (
            <div className="bedrock stack">
              <BedrockHeader model={draft.modelId} />
              <div className="pictos">
                {draft.pictograms.map((p) => (
                  <span key={p} className="row small" style={{ gap: 4 }}>
                    <Icon name={p} size={28} /> {PICTO_LABEL[p]}
                  </span>
                ))}
              </div>
              {draft.noticeLines.length > 0 && (
                <ul className="small" style={{ margin: 0, paddingLeft: 18 }}>
                  {draft.noticeLines.map((line, i) => (
                    <li key={i}>{line}</li>
                  ))}
                </ul>
              )}
              {draft.uncertain.length > 0 && (
                <div className="banner warn small">
                  <span>
                    <strong>Check before approving:</strong> {draft.uncertain.join('; ')}
                  </span>
                </div>
              )}
              {Object.entries(draft.translations).map(([l, t]) => (
                <details key={l}>
                  <summary className="small" style={{ cursor: 'pointer' }}>
                    {LANG_LABEL[l as Lang]} version
                  </summary>
                  <p className="small" style={{ marginTop: 4 }}>
                    <strong>{t?.title}</strong> {t?.body}
                  </p>
                </details>
              ))}
              {draft.radioScript && (
                <details>
                  <summary className="small" style={{ cursor: 'pointer' }}>
                    Radio / loudspeaker script
                  </summary>
                  <p className="small" style={{ marginTop: 4 }}>
                    {draft.radioScript}
                  </p>
                </details>
              )}
            </div>
          )}
          <label className="field">
            Headline
            <input type="text" value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} />
          </label>
          <label className="field">
            Message
            <textarea value={body} maxLength={1000} onChange={(e) => setBody(e.target.value)} />
          </label>
          <div className="approval">
            <div className="row between">
              <strong>Official approval</strong>
              <span className="badge sim">SIMULATED</span>
            </div>
            <p className="small">
              In a real deployment an authorized official signs off here. For this demo, typing a name stands in for that approval.
            </p>
            <input type="text" placeholder="Approver name (fictional)" value={approver} onChange={(e) => setApprover(e.target.value)} aria-label="Approver name" />
            <div className="row">
              <button type="button" className="btn primary" disabled={!approver.trim() || !body.trim() || busy !== null} onClick={publish}>
                {busy === 'publish' ? 'Publishing…' : `Approve & publish to ${zoneName(target)}`}
              </button>
              <button type="button" className="btn ghost" onClick={() => setDraft(null)}>
                Back
              </button>
            </div>
          </div>
        </>
      )}
      {err && <div className="banner warn">{err}</div>}
    </section>
  );
}
