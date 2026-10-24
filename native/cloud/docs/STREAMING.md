# Live speech in RELAY

The native app streams mono PCM16 at 16 kHz through an authenticated WebSocket:
`wss://<API>/v1/speech/<UUID>`. The backend signs a short-lived AWS Transcribe
streaming connection. AWS credentials and signed URLs never reach the app.

The server sends `ready`, incremental `transcript` events keyed by result ID,
then `complete` only after the final text is committed to the durable store.
Partial segments replace earlier versions; a finalized segment cannot regress.
The user reviews the editable transcript and separately sends a shelter request.
A transcript is not an approval, allocation, or delivery receipt.

Limits: 60 seconds, 16 kHz mono signed PCM16, <=8192 bytes per frame, eight-second
client idle timeout, bounded final-result wait, four server leases by default,
and one live session per account. The shared transcription allocation cap also
applies. Same-ID completion replay does not allocate another paid stream.
Cancellation, malformed audio and disconnects never become successful completion.
A crashed session becomes failed after its maximum duration plus 45 seconds.

The app retains a WAV locally. Retry first checks the original transcription ID;
a completed server result is recovered. If that session failed, an explicit retry
may create a new batch Transcribe job from the retained audio. There is no hidden
automatic paid restart. Recordings and transcripts remain synthetic demo data.
Live PCM passes through the Mac API and AWS; it is not end-to-end encrypted from
AWS or the API operator. The backend retains final text and audio hashes/metadata;
it does not upload live audio to S3. Batch uploads use the existing S3 path.

## Reproducible verification

Run `swift test` and `PYTHONPATH=cloud python -m pytest cloud/tests -q` with the
backend virtual environment. Build `swift build --product RelaySpeechCheck` and
run it with `--base-url`, `--session-file`, `--wav`, and `--output`. Use only a
private enrolled test-session file and the repository's synthetic WAV fixture.
The checker refreshes that session in memory, streams paced PCM, verifies durable
HTTP retrieval, and reconnects with the same ID to check cached completion.
Never commit the session file.

Evidence is under `docs/evidence/streaming-20261024/`. A native Swift client and
prerecorded synthetic WAV prove the streaming software path. They do not prove
physical microphone quality, noisy speech accuracy, or offline Wi-Fi transport.
