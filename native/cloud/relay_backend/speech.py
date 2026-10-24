"""Bounded authenticated live speech. AWS credentials/signatures stay on the server."""
import asyncio
from contextlib import asynccontextmanager
import hashlib
import io
import json
import struct
import time
from urllib.parse import urlencode
from uuid import UUID
import wave
import zlib

from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from fastapi import WebSocket, WebSocketDisconnect
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosedOK

from .auth import AuthError
from .common import APIError, PREFIX, digest, key
from .store import Conflict, Put


def audio_event(pcm: bytes) -> bytes:
    headers = bytearray()
    for name, value in ((":content-type", "application/octet-stream"), (":event-type", "AudioEvent"), (":message-type", "event")):
        a, b = name.encode(), value.encode()
        headers.extend(bytes([len(a)]) + a + b"\x07" + struct.pack(">H", len(b)) + b)
    prelude = struct.pack(">II", 16 + len(headers) + len(pcm), len(headers))
    frame = prelude + struct.pack(">I", zlib.crc32(prelude)) + headers + pcm
    return frame + struct.pack(">I", zlib.crc32(frame))


def decode_event(frame: bytes):
    if not isinstance(frame, bytes) or not 16 <= len(frame) <= 262144:
        raise ValueError("Invalid event size")
    length, header_length, crc = struct.unpack(">III", frame[:12])
    if length != len(frame) or header_length > length - 16 or crc != zlib.crc32(frame[:8]) or struct.unpack(">I", frame[-4:])[0] != zlib.crc32(frame[:-4]):
        raise ValueError("Invalid event checksum or length")
    headers, at, end = {}, 12, 12 + header_length
    while at < end:
        size = frame[at]; at += 1
        if size == 0 or at + size + 3 > end:
            raise ValueError("Invalid event header")
        name = frame[at:at + size].decode(); at += size
        if frame[at] != 7:
            raise ValueError("Unsupported event header type")
        at += 1
        size = struct.unpack(">H", frame[at:at + 2])[0]; at += 2
        if at + size > end or name in headers:
            raise ValueError("Invalid event header value")
        headers[name] = frame[at:at + size].decode(); at += size
    return headers, frame[end:-4]


def signed_stream_url(settings, session_id):
    credentials = settings.aws_session().get_credentials().get_frozen_credentials()
    host = "transcribestreaming." + settings.aws_region + ".amazonaws.com:8443"
    params = {"language-code": "en-US", "media-encoding": "pcm", "sample-rate": "16000",
              "session-id": session_id, "enable-partial-results-stabilization": "true",
              "partial-results-stability": "medium"}
    request = AWSRequest(method="GET", url="https://" + host + "/stream-transcription-websocket?" + urlencode(params))
    SigV4QueryAuth(credentials, "transcribe", settings.aws_region, expires=60).add_auth(request)
    return "wss://" + request.url.split("://", 1)[1]


@asynccontextmanager
async def aws_stream(settings, session_id):
    # Never log this presigned URL; it is a short-lived server-side credential.
    url = await asyncio.to_thread(signed_stream_url, settings, session_id)
    async with connect(url, open_timeout=10, close_timeout=2, max_size=262144,
                       compression=None, proxy=None) as socket:
        yield socket


class TranscriptAccumulator:
    def __init__(self):
        self.parts = {}

    def update(self, result):
        identifier = result.get("ResultId")
        alternatives = result.get("Alternatives") or []
        if not isinstance(identifier, str) or not alternatives:
            return None
        text = alternatives[0].get("Transcript", "")
        if not isinstance(text, str) or len(text) > 4096:
            raise ValueError("Transcript exceeds limit")
        partial = bool(result.get("IsPartial", True))
        old = self.parts.get(identifier)
        if old and not old["is_partial"]:
            return None  # Do not regress a finalized segment on duplicate/out-of-order events.
        event = {"type": "transcript", "result_id": identifier, "text": text,
                 "is_partial": partial, "start_time": float(result.get("StartTime", 0))}
        self.parts[identifier] = event
        if len(self.parts) > 256 or sum(len(x["text"]) for x in self.parts.values()) > 4096:
            raise ValueError("Transcript exceeds limit")
        return event

    def final_text(self):
        return " ".join(x["text"] for x in sorted(self.parts.values(), key=lambda x: (x["start_time"], x["result_id"]))
                        if not x["is_partial"]).strip()


def claim_speech(service, principal, identifier):
    service.writable()
    now = service.clock()
    existing = service.store.get(*key("transcription", identifier))
    if existing:
        if existing[0]["owner_subject"] != principal.subject:
            raise APIError(404, "transcription_not_found", "Recording not found")
        if existing[0]["status"] == "completed":
            return existing[0], None
        raise APIError(409, "stream_not_resumable", "This live session ended or is already active. Start a new recording.")
    owner_key = key("speech_owner", principal.subject)
    slot_keys = [key("speech_slot", str(i)) for i in range(service.settings.max_live_streams)]
    rows = service.store.get_many([owner_key, *slot_keys])
    owner = rows[owner_key]
    if owner and owner[0]["expires_at"] > now:
        raise APIError(429, "speech_busy", "A recording is already active for this account.", True)
    available = next((k for k in slot_keys if rows[k] is None or rows[k][0]["expires_at"] <= now), None)
    if available is None:
        raise APIError(429, "speech_busy", "All live recording slots are busy. Try again shortly.", True)
    lease = {"session_id": identifier, "expires_at": now + service.settings.max_audio_seconds + 45}
    record = {"schema_version": 1, "transcription_id": identifier, "operation_id": identifier,
              "incident_id": principal.membership.incident_id, "owner_subject": principal.subject,
              "payload_hash": digest({"session_id": identifier, "mode": "stream"}),
              "content_type": "audio/wav", "byte_length": 0, "sha256": "0" * 64,
              "language_code": "en-US", "status": "processing", "created_at": now,
              "upload_expires_at": now, "transcript": None, "error": None,
              "provider_evidence": {"provider": service.settings.mode, "transport": "streaming"},
              "start_operation_id": identifier, "start_count": 1, "started_at": now,
              "sample_rate": 16000}
    try:
        service.store.transact(puts=[Put(*key("transcription", identifier), record),
            Put(*owner_key, lease, owner[1] if owner else None),
            Put(*available, lease, rows[available][1] if rows[available] else None),
            service.budget_put("transcriptions")])
    except Conflict:
        raise APIError(409, "concurrent_speech_start", "Another recording started at the same time. Retry shortly.", True) from None
    return record, (owner_key, available)


def finish_speech(service, principal, identifier, slots, pcm, transcript=None, error=None, evidence=None):
    row = service.owned_audio(principal, identifier)
    record = row[0]
    if record["status"] != "processing":
        return
    out = io.BytesIO()
    with wave.open(out, "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(16000); wav.writeframes(pcm)
    data = out.getvalue()
    record = {**record, "status": "completed" if transcript else "failed", "transcript": transcript,
              "error": error, "byte_length": len(data), "sha256": hashlib.sha256(data).hexdigest(),
              "duration_seconds": len(pcm) / 32000,
              "provider_evidence": {**record["provider_evidence"], **(evidence or {})}}
    puts = [Put(*key("transcription", identifier), record, row[1])]
    for slot in slots:
        current = service.store.get(*slot)
        if current and current[0]["session_id"] == identifier:
            puts.append(Put(*slot, {"session_id": identifier, "expires_at": 0}, current[1]))
    service.store.transact(puts=puts)


def install_speech_routes(app, service, auth):
    @app.websocket("/v1/speech/{session_id}")
    async def speech(socket: WebSocket, session_id: str):
        try:
            if str(UUID(session_id)) != session_id:
                raise ValueError()
            user = await asyncio.to_thread(auth.verify, socket.headers.get("authorization"))
        except (AuthError, ValueError):
            await socket.close(code=1008); return
        await socket.accept()
        slots, pcm = None, bytearray()
        started = time.monotonic()
        accumulator = TranscriptAccumulator()
        evidence = {}
        try:
            record, slots = await asyncio.to_thread(claim_speech, service, user, session_id)
            if slots is None:
                await socket.send_json({"type": "complete", "transcription_id": session_id, "text": record["transcript"], "cached": True})
                return
            factory = getattr(app.state, "speech_factory", None)
            if factory is None and service.settings.mode != "aws":
                raise APIError(503, "streaming_unconfigured", "Live speech requires the AWS provider.")
            async with asyncio.timeout(service.settings.max_audio_seconds + 25):
                async with (factory(service.settings, session_id) if factory else aws_stream(service.settings, session_id)) as upstream:
                    headers = getattr(getattr(upstream, "response", None), "headers", {})
                    evidence["request_id"] = headers.get("x-amzn-request-id")
                    await socket.send_json({"type": "ready", "transcription_id": session_id, "sample_rate": 16000,
                                            "max_seconds": service.settings.max_audio_seconds})
                    async def feed():
                        ready_at = time.monotonic()
                        while True:
                            packet = await asyncio.wait_for(socket.receive(), timeout=8)
                            if packet["type"] == "websocket.disconnect":
                                raise APIError(499, "stream_disconnected", "Recording interrupted. Review saved audio before retrying.")
                            chunk = packet.get("bytes")
                            if chunk is not None:
                                if len(chunk) == 0 or len(chunk) > 8192 or len(chunk) % 2:
                                    raise APIError(422, "invalid_audio_chunk", "Use mono PCM16 audio at 16 kHz.")
                                if len(pcm) + len(chunk) > service.settings.max_audio_seconds * 32000 or time.monotonic() - ready_at > service.settings.max_audio_seconds + 2:
                                    raise APIError(413, "audio_duration_limit", "Recording is limited to 60 seconds.")
                                pcm.extend(chunk)
                                await upstream.send(audio_event(chunk))
                            else:
                                text = packet.get("text", "")
                                if len(text) > 256:
                                    raise APIError(422, "invalid_stream_control", "Invalid recording control.")
                                control = json.loads(text)
                                if control == {"type": "finish"}:
                                    if not pcm:
                                        raise APIError(422, "empty_audio", "No audio was recorded.")
                                    await upstream.send(audio_event(b"")); return
                                if control == {"type": "cancel"}:
                                    raise APIError(499, "stream_cancelled", "Recording cancelled.")
                                raise APIError(422, "invalid_stream_control", "Invalid recording control.")
                    async def read():
                        async for message in upstream:
                            headers, payload = decode_event(message)
                            if headers.get(":message-type") == "exception":
                                code = headers.get(":exception-type", "stream_provider_error")
                                raise APIError(503, code, "Speech service could not complete this recording.", True)
                            if headers.get(":event-type") != "TranscriptEvent":
                                raise APIError(503, "unexpected_speech_event", "Speech service returned an unsupported event.")
                            body = json.loads(payload)
                            for result in body.get("Transcript", {}).get("Results", []):
                                event = accumulator.update(result)
                                if event:
                                    evidence.setdefault("first_result_ms", round((time.monotonic() - started) * 1000))
                                    await socket.send_json(event)
                    reader, feeder = asyncio.create_task(read()), asyncio.create_task(feed())
                    try:
                        done, _ = await asyncio.wait([reader, feeder], return_when=asyncio.FIRST_COMPLETED)
                        if reader in done:
                            await reader
                            if not feeder.done():
                                raise APIError(503, "stream_ended_early", "Speech connection ended before recording finished.", True)
                        await feeder
                        await asyncio.wait_for(reader, timeout=15)
                    finally:
                        for task in (reader, feeder):
                            if not task.done(): task.cancel()
                        await asyncio.gather(reader, feeder, return_exceptions=True)
            final = accumulator.final_text()
            if not final:
                raise APIError(422, "no_speech", "No speech was recognized. Speak clearly or type your request.")
            evidence["total_ms"] = round((time.monotonic() - started) * 1000)
            await asyncio.to_thread(finish_speech, service, user, session_id, slots, bytes(pcm), final, None, evidence)
            slots = None
            await socket.send_json({"type": "complete", "transcription_id": session_id, "text": final})
        except Exception as exc:
            if isinstance(exc, APIError):
                error = {"code": exc.code, "message": exc.message, "retryable": exc.retryable}
            else:
                # Never include exception strings: WebSocket errors may contain signed URLs.
                error = {"code": "stream_interrupted", "message": "Live transcription was interrupted. Your local recording can be reviewed or retried.", "retryable": True}
            if slots:
                try:
                    await asyncio.to_thread(finish_speech, service, user, session_id, slots, bytes(pcm), None, error, evidence)
                except Exception:
                    pass  # Lease expiry permits future sessions; no false completed result is sent.
            try: await socket.send_json({"type": "error", **error})
            except Exception: pass
        finally:
            try: await socket.close()
            except Exception: pass
