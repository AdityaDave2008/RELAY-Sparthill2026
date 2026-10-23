import { useState, type ReactNode } from 'react';
import { api } from '../api/index.ts';
import { LANG_LABEL, parseRequestBody, type CardReading, type Lang, type Need, type Pictogram, type WarningDraft, type WireMessage } from '../contract.ts';
import { useDevice } from '../device/device.ts';
import { BedrockHeader, clock, SimulationBanner, timeAgo, Toast, TopBar, useNow, useToast } from '../ui/common.tsx';
import { Icon, NEED_LABEL, PICTO_LABEL } from '../ui/icons.tsx';
import { ZONES, zoneName } from '../zones.ts';

interface Notice {
  title: string;
  body: string;
  translations: WarningDraft['translations'];
  noticeLines?: string[];
  pictograms: Pictogram[];
  radioScript: string;
  issuedAt: number;
  expiresAt: number;
  approved: boolean;
}

const PICTO_FOR_WORDS: [Pictogram, RegExp][] = [
  ['water', /water/i],
  ['food', /food|meal/i],
  ['medical', /medic|clinic|insulin/i],
  ['shelter', /shelter|gym|school/i],
  ['danger', /avoid|danger|closed|flood|fire/i],
  ['route', /route|road|bridge/i],
];

// The latest notice for a zone: the coordinator's published draft (same
// browser), otherwise the newest warning this phone has received.
function useNotice(zoneId: string): Notice | null {
  const d = useDevice();
  try {
    const saved = localStorage.getItem(`relay.notice.${zoneId}`);
    if (saved) {
      const n = JSON.parse(saved) as WarningDraft & { publishedAt: number };
      return { ...n, issuedAt: n.publishedAt, expiresAt: n.publishedAt + 12 * 3600_000, approved: true };
    }
  } catch {
    // fall through to the device copy
  }
  const w: WireMessage | undefined = d.warnings().find((m) => m.incidentId === zoneId) ?? d.warnings()[0];
  if (!w) return null;
  const text = `${w.title ?? ''} ${w.body}`;
  const pictograms = PICTO_FOR_WORDS.filter(([, re]) => re.test(text)).map(([p]) => p);
  return {
    title: w.title ?? w.body.split(/[.!?]/)[0],
    body: w.body,
    translations: w.translations ?? {},
    pictograms: pictograms.length ? pictograms : ['info'],
    radioScript: '',
    issuedAt: w.createdAt,
    expiresAt: w.expiresAt,
    approved: true,
  };
}

export function Volunteer({ zoneId: initial }: { zoneId?: string }) {
  const [zoneId, setZoneId] = useState(initial ?? ZONES.find((z) => z.connectivity === 'offline')!.id);
  const zone = ZONES.find((z) => z.id === zoneId)!;
  const notice = useNotice(zoneId);
  const noDevice = Math.round(zone.population * zone.reach.none);
  const radioOnly = Math.round(zone.population * zone.reach.radio);

  return (
    <>
      <TopBar role="Volunteer · last-mile delivery" />
      <main className="page narrow stack-lg">
        <div className="stack">
          <h1>Reach people without phones</h1>
          <p className="muted">Turn the latest official warning into a printed notice and a spoken announcement, then bring paper help cards back.</p>
        </div>
        <label className="field">
          Area
          <select value={zoneId} onChange={(e) => setZoneId(e.target.value)}>
            {ZONES.map((z) => (
              <option key={z.id} value={z.id}>
                {z.name} ({z.connectivity === 'offline' ? 'no signal' : z.connectivity})
              </option>
            ))}
          </select>
        </label>

        <div className="card stack">
          <h2>Who needs a non-digital message in {zone.name}</h2>
          <div className="grid-2" style={{ gap: 8 }}>
            <div className="row">
              <Icon name="radio" size={28} />
              <span>
                <strong>~{radioOnly}</strong> radio only
              </span>
            </div>
            <div className="row">
              <Icon name="paper" size={28} />
              <span>
                <strong>~{noDevice}</strong> no device at all
              </span>
            </div>
          </div>
          <p className="small muted">Estimates for the fictional demo area.</p>
        </div>

        <section className="stack">
          <div className="section-title">
            <h2>1 · Post the notice</h2>
          </div>
          {notice ? (
            <div className="card stack">
              <div className="row">
                {notice.pictograms.map((p) => (
                  <Icon key={p} name={p} size={32} title={PICTO_LABEL[p]} />
                ))}
              </div>
              <h3>{notice.title}</h3>
              {notice.noticeLines?.length ? (
                <ul className="small" style={{ margin: 0, paddingLeft: 18 }}>
                  {notice.noticeLines.map((line, i) => (
                    <li key={i}>{line}</li>
                  ))}
                </ul>
              ) : (
                <p className="small">{notice.body}</p>
              )}
              <a className="btn dark" href={`#/print/notice/${zoneId}`}>
                <Icon name="paper" size={18} /> Open printable notice
              </a>
            </div>
          ) : (
            <div className="card flat">
              <p className="muted">No approved warning for this area yet. One appears here once a coordinator publishes it, or once your phone receives it from a nearby phone.</p>
            </div>
          )}
        </section>

        <section className="stack">
          <div className="section-title">
            <h2>2 · Read it aloud</h2>
          </div>
          <div className="card stack">
            <p className="small muted">Read this slowly through a loudspeaker or at doorsteps, twice. Radio stations can broadcast the same text.</p>
            <p style={{ fontSize: '1.1rem', lineHeight: 1.6 }}>
              {notice ? notice.radioScript || `Emergency update for ${zone.name}. ${notice.body} Again: ${notice.title}.` : '—'}
            </p>
            {notice && 'speechSynthesis' in window && (
              <button type="button" className="btn" onClick={() => speak(notice.radioScript || `${notice.title}. ${notice.body}`)}>
                <Icon name="radio" size={18} /> Play on this phone's speaker
              </button>
            )}
          </div>
        </section>

        <section className="stack">
          <div className="section-title">
            <h2>3 · Hand out help cards</h2>
          </div>
          <div className="card stack">
            <p className="small">Residents tick what they need and give the card back to you. No reading or writing required beyond the pictures.</p>
            <a className="btn" href={`#/print/card/${zoneId}`}>
              <Icon name="paper" size={18} /> Open printable help card
            </a>
          </div>
        </section>

        <PaperEntry zoneId={zoneId} />
      </main>
    </>
  );
}

function speak(text: string) {
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.rate = 0.9;
  speechSynthesis.speak(u);
}

const CARD_NEEDS: Need[] = ['water', 'food', 'medical', 'shelter', 'evacuation', 'power'];

function PaperEntry({ zoneId }: { zoneId: string }) {
  const d = useDevice();
  const now = useNow();
  const [volunteer, setVolunteer] = useState(() => localStorage.getItem('relay.volunteer') ?? '');
  const [needs, setNeeds] = useState<Need[]>([]);
  const [people, setPeople] = useState('');
  const [where, setWhere] = useState('');
  const [notes, setNotes] = useState('');
  const [toast, showToast] = useToast();
  const [reading, setReading] = useState<CardReading | null>(null);
  const [readBusy, setReadBusy] = useState(false);
  const [readErr, setReadErr] = useState<string | null>(null);
  const cards = d.paperRequests().filter((m) => m.incidentId === zoneId);

  // Bedrock vision reads a photo of the returned card and pre-fills the form.
  // The volunteer checks every field before saving.
  async function readPhoto(file: File) {
    setReadBusy(true);
    setReadErr(null);
    try {
      const { base64, mediaType } = await shrinkImage(file);
      const r = await api.readCard({ imageBase64: base64, mediaType, incidentId: zoneId });
      setReading(r);
      setNeeds(r.needs);
      setPeople(r.peopleCount ? String(r.peopleCount) : '');
      setWhere(r.locationDescription ?? '');
      setNotes(r.notes);
    } catch (e) {
      setReadErr(
        navigator.onLine
          ? `Bedrock couldn't read the photo (${e instanceof Error ? e.message : e}). Enter it by hand below.`
          : 'Reading a photo needs a connection. Enter the card by hand, or read it once you are back in coverage.',
      );
    } finally {
      setReadBusy(false);
    }
  }

  function save() {
    try {
      localStorage.setItem('relay.volunteer', volunteer);
    } catch {
      // not remembered
    }
    d.addPaperRequest({
      zoneId,
      volunteer,
      needs,
      people: people ? Number(people) : null,
      notes: [where && `Location: ${where}.`, notes].filter(Boolean).join(' '),
    });
    setNeeds([]);
    setPeople('');
    setWhere('');
    setNotes('');
    setReading(null);
    showToast(d.sync.online ? 'Card saved and sending' : 'Card saved. It will send when you have a connection.');
  }

  return (
    <section className="stack">
      <div className="section-title">
        <h2>4 · Enter returned cards</h2>
      </div>
      <div className="card stack">
        <label className="btn dark" style={{ cursor: readBusy ? 'wait' : 'pointer' }}>
          <Icon name="sparkle" size={18} />
          {readBusy ? 'Reading the card…' : api.mode === 'mock' ? 'Photograph card (mock AI)' : 'Photograph card · Amazon Bedrock reads it'}
          <input
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            disabled={readBusy}
            onChange={(e) => {
              const f = e.target.files?.[0];
              e.target.value = '';
              if (f) void readPhoto(f);
            }}
          />
        </label>
        {readErr && <div className="banner warn small">{readErr}</div>}
        {reading && (
          <div className="bedrock stack" style={{ gap: 4 }}>
            <BedrockHeader model={reading.modelId} requestId={reading.awsRequestId} />
            <p className="small">Fields below were filled in from the photo. Check them against the card before saving.</p>
            {reading.unreadable.length > 0 && <p className="small" style={{ color: 'var(--warn)' }}>Couldn't read: {reading.unreadable.join(', ')}</p>}
          </div>
        )}
        <label className="field">
          Your name (volunteer)
          <input type="text" value={volunteer} onChange={(e) => setVolunteer(e.target.value)} placeholder="e.g. Sam R." />
        </label>
        <div className="chips">
          {CARD_NEEDS.map((n) => (
            <button
              key={n}
              type="button"
              className="chip"
              aria-pressed={needs.includes(n)}
              onClick={() => setNeeds((c) => (c.includes(n) ? c.filter((x) => x !== n) : [...c, n]))}
            >
              <Icon name={n} /> {NEED_LABEL[n]}
            </button>
          ))}
        </div>
        <div className="grid-2" style={{ gap: 8 }}>
          <label className="field">
            People
            <input type="number" inputMode="numeric" min={1} value={people} onChange={(e) => setPeople(e.target.value)} />
          </label>
          <label className="field">
            Where (as written on card)
            <input type="text" value={where} onChange={(e) => setWhere(e.target.value)} placeholder="e.g. 14 Oak Lane, blue door" />
          </label>
        </div>
        <label className="field">
          Anything else written on the card
          <textarea value={notes} onChange={(e) => setNotes(e.target.value)} />
        </label>
        <button type="button" className="btn primary" disabled={!volunteer.trim() || (needs.length === 0 && !notes.trim())} onClick={save}>
          Save card
        </button>
      </div>
      {cards.length > 0 && (
        <div className="stack">
          {cards.map((m) => {
            const p = parseRequestBody(m.body);
            const { state } = d.delivery(m.id);
            return (
              <div key={m.id} className="card flat row between">
                <span className="small">
                  {p.needs.map((n) => NEED_LABEL[n]).join(', ') || 'Note'} · {p.people ?? '?'} people · {timeAgo(m.createdAt, now)}
                </span>
                <span className={`badge ${state === 'saved' ? 'warn' : 'ok'}`}>
                  {state === 'saved' ? 'On this phone' : state === 'relayed' ? 'Passed on' : state === 'uploaded' ? 'Reached coordinators' : 'Answered'}
                </span>
              </div>
            );
          })}
        </div>
      )}
      <Toast msg={toast} />
    </section>
  );
}

export function PrintNotice({ zoneId }: { zoneId: string }) {
  const notice = useNotice(zoneId);
  const zone = zoneName(zoneId);
  return (
    <PrintShell back={`#/volunteer/${zoneId}`} label="Printable notice">
      {!notice ? (
        <p className="muted">No approved warning for {zone} yet.</p>
      ) : (
        <article className="sheet notice stack-lg">
          <div className="row between">
            <span className="stamp">EMERGENCY NOTICE · {zone.toUpperCase()}</span>
            <span className="stamp">DEMO · FICTIONAL</span>
          </div>
          <div className="pictos">
            {notice.pictograms.map((p) => (
              <div key={p} style={{ display: 'grid', justifyItems: 'center', gap: 4 }}>
                <Icon name={p} />
                <strong>{PICTO_LABEL[p]}</strong>
              </div>
            ))}
          </div>
          <h1>{notice.title}</h1>
          <p className="big">{notice.body}</p>
          {(Object.entries(notice.translations) as [Lang, { title: string; body: string }][]).map(([l, t]) => (
            <div key={l} className="lang-block">
              <p>
                <strong>{LANG_LABEL[l]}:</strong> <strong>{t.title}</strong>
              </p>
              <p className="big">{t.body}</p>
            </div>
          ))}
          <div className="lang-block small">
            <p>
              Issued {new Date(notice.issuedAt).toLocaleString()} · Valid until {clock(notice.expiresAt)} ({new Date(notice.expiresAt).toLocaleDateString()})
            </p>
            <p>Source: Riverbend County emergency coordinators (fictional, simulated approval). Information may change; check for newer notices.</p>
          </div>
        </article>
      )}
    </PrintShell>
  );
}

export function PrintCard({ zoneId }: { zoneId: string }) {
  const zone = zoneName(zoneId);
  const card = (
    <article className="sheet helpcard stack-lg">
      <div className="row between">
        <h1 style={{ fontSize: '1.8rem' }}>NEED HELP? · ¿NECESITA AYUDA?</h1>
        <span className="stamp">{zone.toUpperCase()}</span>
      </div>
      <p className="big" style={{ fontSize: '1.15rem' }}>
        Tick what you need ✓ and give this card back to the volunteer. · Marque lo que necesita ✓ y devuelva esta tarjeta al voluntario.
      </p>
      <div className="grid">
        {CARD_NEEDS.map((n) => (
          <div key={n} className="box">
            <span className="tick" />
            <Icon name={n} />
            <span>{NEED_LABEL[n]}</span>
          </div>
        ))}
      </div>
      <div className="row" style={{ alignItems: 'flex-end', gap: 16 }}>
        <Icon name="people" size={48} />
        <span style={{ fontSize: '1.2rem', fontWeight: 700 }}>How many people? / ¿Cuántas personas?</span>
        <span className="line" style={{ flex: 1 }} />
      </div>
      <div className="row" style={{ alignItems: 'flex-end', gap: 16 }}>
        <Icon name="pin" size={48} />
        <span style={{ fontSize: '1.2rem', fontWeight: 700 }}>Where? / ¿Dónde?</span>
        <span className="line" style={{ flex: 1 }} />
      </div>
      <div className="line" />
      <p className="small">RELAY demo · fictional area · Volunteers bring cards to the coordinators, and replies come back to you the same way.</p>
    </article>
  );
  return (
    <PrintShell back={`#/volunteer/${zoneId}`} label="Printable help card">
      {card}
    </PrintShell>
  );
}

function PrintShell({ back, label, children }: { back: string; label: string; children: ReactNode }) {
  return (
    <>
      <TopBar role={label} />
      <main className="page stack-lg">
        <div className="no-print stack">
          <SimulationBanner>Fictional demo content. The approval shown on notices is simulated.</SimulationBanner>
          <div className="row">
            <a className="btn" href={back}>
              ← Back
            </a>
            <button type="button" className="btn dark" onClick={() => window.print()}>
              Print
            </button>
          </div>
          <p className="small muted">No printer? Hold this screen up or copy it by hand. The pictures carry the message.</p>
        </div>
        {children}
      </main>
    </>
  );
}

// Phone photos are several MB; Bedrock only needs a readable card.
async function shrinkImage(file: File, maxSide = 1400): Promise<{ base64: string; mediaType: string }> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
  return { base64: dataUrl.slice(dataUrl.indexOf(',') + 1), mediaType: 'image/jpeg' };
}
