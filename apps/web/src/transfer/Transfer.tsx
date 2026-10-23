// Phone-to-phone transfer over QR codes, with no network.
//
//   sender                         receiver
//   shows message codes   ──────▶  scans, TransferReceiver checks and stores
//   scans receipt code    ◀──────  shows a receipt with the ids it now holds
//   marks them "relayed"
//
// The receipt is what makes "relayed" honest: a message is only marked
// relayed once the other phone has confirmed it holds it.
import { encodeTransfer, offer, TransferReceiver } from '@relay/core';
import { useMemo, useState } from 'react';
import { useDevice } from '../device/device.ts';
import { Icon } from '../ui/icons.tsx';
import { QrScanner, QrSequence } from './qr.tsx';

interface Receipt {
  protocol: 'relay-receipt';
  version: 1;
  peer: string;
  ids: string[];
}

function parseReceipt(text: string): Receipt | null {
  try {
    const r = JSON.parse(text) as Receipt;
    if (r?.protocol !== 'relay-receipt' || r.version !== 1 || typeof r.peer !== 'string' || !Array.isArray(r.ids)) return null;
    if (r.ids.length > 50 || r.ids.some((id) => typeof id !== 'string' || id.length > 64)) return null;
    return { protocol: r.protocol, version: 1, peer: r.peer.slice(0, 64), ids: r.ids };
  } catch {
    return null;
  }
}

type Step =
  | { name: 'idle' }
  | { name: 'sending'; frames: string[]; ids: string[] }
  | { name: 'scanning-receipt'; frames: string[]; ids: string[] }
  | { name: 'sent'; count: number; peer: string }
  | { name: 'receiving'; received: number; total: number }
  | { name: 'received'; added: number; already: number; receipt: string };

export function QrTransfer() {
  const d = useDevice();
  const [step, setStep] = useState<Step>({ name: 'idle' });
  const [err, setErr] = useState<string | null>(null);
  // One receiver per receiving session, so partial transfers are kept.
  const receiver = useMemo(() => new TransferReceiver(d.store), [d.store]);
  const forwardable = offer(d.store).ids.length;

  async function startSend() {
    setErr(null);
    try {
      const ids = offer(d.store).ids.slice(0, 50);
      const frames = await encodeTransfer(d.store, { ids });
      if (!frames.length) return setErr('Nothing on this phone to pass on yet.');
      setStep({ name: 'sending', frames, ids });
    } catch (e) {
      setErr(`Could not prepare the transfer: ${e instanceof Error ? e.message : e}`);
    }
  }

  async function onTransferCode(text: string) {
    setErr(null);
    let progress;
    try {
      progress = await receiver.accept(text);
    } catch (e) {
      if (parseReceipt(text)) return setErr('That is a receipt code. Scan the code on the sending phone instead.');
      return setErr(`Ignored a code that is not a RELAY transfer (${e instanceof Error ? e.message : e}).`);
    }
    if (!progress.complete) return setStep({ name: 'receiving', received: progress.received, total: progress.total });
    d.commit(); // save to the phone and refresh the screens
    const duplicates = progress.report.rejected.filter((r) => r.reason === 'duplicate').map((r) => r.id);
    const holds = [...progress.report.added, ...duplicates];
    const receipt: Receipt = { protocol: 'relay-receipt', version: 1, peer: d.deviceId, ids: holds };
    setStep({ name: 'received', added: progress.report.added.length, already: duplicates.length, receipt: JSON.stringify(receipt) });
  }

  function onReceiptCode(text: string, sentIds: string[]) {
    const r = parseReceipt(text);
    if (!r) return setErr('Not a receipt yet. Scan the receipt code shown on the other phone.');
    const confirmed = r.ids.filter((id) => sentIds.includes(id));
    d.recordRelay(confirmed, r.peer);
    setStep({ name: 'sent', count: confirmed.length, peer: r.peer });
  }

  return (
    <section className="card flat stack">
      <div className="row between">
        <h2>Pass messages to a nearby phone</h2>
        <span className="badge neutral">No signal needed</span>
      </div>

      {step.name === 'idle' && (
        <>
          <p className="small muted">
            Works with no internet or cell service. One phone shows codes, the other scans them with its camera. Requests, warnings and
            replies travel this way until one phone reaches signal.
          </p>
          <div className="row">
            <button type="button" className="btn dark" onClick={startSend} disabled={forwardable === 0}>
              <Icon name="phone" size={18} /> Send {forwardable ? `(${forwardable})` : ''}
            </button>
            <button type="button" className="btn" onClick={() => setStep({ name: 'receiving', received: 0, total: 0 })}>
              Receive
            </button>
          </div>
        </>
      )}

      {step.name === 'sending' && (
        <>
          <p className="small">
            <strong>Step 1 of 2.</strong> Point the other phone's RELAY <em>Receive</em> camera at this code.
          </p>
          <QrSequence frames={step.frames} label="Transfer code" />
          <button type="button" className="btn primary" onClick={() => setStep({ ...step, name: 'scanning-receipt' })}>
            The other phone shows a receipt: scan it
          </button>
          <button type="button" className="btn ghost" onClick={() => setStep({ name: 'idle' })}>
            Cancel
          </button>
        </>
      )}

      {step.name === 'scanning-receipt' && (
        <>
          <p className="small">
            <strong>Step 2 of 2.</strong> Scan the receipt code on the other phone. Messages are only marked <em>relayed</em> once it
            confirms it has them.
          </p>
          <QrScanner onCode={(t) => onReceiptCode(t, step.ids)} />
          <button type="button" className="btn ghost" onClick={() => setStep({ ...step, name: 'sending' })}>
            Back to the transfer code
          </button>
        </>
      )}

      {step.name === 'sent' && (
        <>
          <div className="banner" style={{ background: 'var(--ok-soft)', color: '#064e3b' }}>
            <Icon name="check" size={18} />
            <span>
              {step.count} message{step.count === 1 ? '' : 's'} confirmed by {step.peer}.
            </span>
          </div>
          <button type="button" className="btn" onClick={() => setStep({ name: 'idle' })}>
            Done
          </button>
        </>
      )}

      {step.name === 'receiving' && (
        <>
          <p className="small">Point the camera at the code on the sending phone.</p>
          <QrScanner onCode={onTransferCode} />
          {step.total > 1 && (
            <p className="small muted">
              Got {step.received} of {step.total} codes…
            </p>
          )}
          <button type="button" className="btn ghost" onClick={() => setStep({ name: 'idle' })}>
            Cancel
          </button>
        </>
      )}

      {step.name === 'received' && (
        <>
          <div className="banner" style={{ background: 'var(--ok-soft)', color: '#064e3b' }}>
            <Icon name="check" size={18} />
            <span>
              Received {step.added} new message{step.added === 1 ? '' : 's'}
              {step.already ? ` (${step.already} already on this phone)` : ''}. Checked and saved.
            </span>
          </div>
          <p className="small">Now let the sending phone scan this receipt:</p>
          <QrSequence frames={[step.receipt]} label="Receipt code" />
          <button type="button" className="btn" onClick={() => setStep({ name: 'idle' })}>
            Done
          </button>
        </>
      )}

      {err && <div className="banner warn small">{err}</div>}
    </section>
  );
}
