// QR building blocks for offline transfer: show a sequence of codes, and scan
// codes with the camera. jsQR is used instead of BarcodeDetector because
// iPhone Safari does not have BarcodeDetector. Camera access needs HTTPS.
import jsQR from 'jsqr';
import QRCode from 'qrcode';
import { useEffect, useRef, useState } from 'react';

// Cycles through the frames so a scanner picks up every one of them.
export function QrSequence({ frames, intervalMs = 700, label }: { frames: string[]; intervalMs?: number; label: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    setIndex(0);
    if (frames.length < 2) return;
    const t = setInterval(() => setIndex((i) => (i + 1) % frames.length), intervalMs);
    return () => clearInterval(t);
  }, [frames, intervalMs]);

  useEffect(() => {
    const text = frames[index];
    if (!canvas.current || !text) return;
    // jsQR (our scanner) cannot read QR version 23 at all, so draw those one
    // size up. Every other version from 12 to 24 decoded 100% in testing.
    const natural = QRCode.create(text, { errorCorrectionLevel: 'L' }).version;
    void QRCode.toCanvas(canvas.current, text, {
      errorCorrectionLevel: 'L',
      margin: 4,
      width: 360,
      ...(natural === 23 ? { version: 24 } : {}),
    });
  }, [frames, index]);

  return (
    <figure className="qr stack" style={{ margin: 0, justifyItems: 'center' }}>
      <canvas ref={canvas} aria-label={label} style={{ width: '100%', maxWidth: 360, height: 'auto', background: '#fff', borderRadius: 8 }} />
      {frames.length > 1 && (
        <figcaption className="small muted">
          Code {index + 1} of {frames.length}. Keep the other phone pointed here until it says it has all of them.
        </figcaption>
      )}
    </figure>
  );
}

// Calls onCode for each new code the camera sees. The same text is not
// reported twice in a row.
export function QrScanner({ onCode, active = true }: { onCode: (text: string) => void; active?: boolean }) {
  const video = useRef<HTMLVideoElement>(null);
  const handler = useRef(onCode);
  handler.current = onCode;
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!active) return;
    let stream: MediaStream | undefined;
    let raf = 0;
    let stopped = false;
    let last = '';
    const work = document.createElement('canvas');
    const ctx = work.getContext('2d', { willReadFrequently: true });

    function tick() {
      if (stopped) return;
      const v = video.current;
      if (v && ctx && v.readyState >= v.HAVE_ENOUGH_DATA && v.videoWidth) {
        // Downscale for speed; dense codes still read at 640 px.
        const scale = Math.min(1, 640 / Math.max(v.videoWidth, v.videoHeight));
        work.width = Math.round(v.videoWidth * scale);
        work.height = Math.round(v.videoHeight * scale);
        ctx.drawImage(v, 0, 0, work.width, work.height);
        const img = ctx.getImageData(0, 0, work.width, work.height);
        const code = jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
        if (code?.data && code.data !== last) {
          last = code.data;
          handler.current(code.data);
        }
      }
      raf = requestAnimationFrame(tick);
    }

    (async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError(
          window.isSecureContext
            ? 'This browser cannot use the camera.'
            : 'The camera needs a secure (https://) page. Open RELAY over HTTPS.',
        );
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
        if (stopped) return stream.getTracks().forEach((t) => t.stop());
        const v = video.current!;
        v.srcObject = stream;
        await v.play();
        raf = requestAnimationFrame(tick);
      } catch (e) {
        setError(`Camera unavailable: ${e instanceof Error ? e.message : e}. Allow camera access and try again.`);
      }
    })();

    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [active]);

  if (error) return <div className="banner warn">{error}</div>;
  return (
    <video
      ref={video}
      playsInline
      muted
      aria-label="Camera view for scanning"
      style={{ width: '100%', maxWidth: 420, borderRadius: 12, background: '#000', justifySelf: 'center' }}
    />
  );
}
