import hashlib
import io
import json
import re
import wave
import time
from pathlib import Path

from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from .analysis import NUMBER_WORDS, SYSTEM_PROMPT, prompt, extraction_tool, structured_output


class ProviderError(Exception):
    def __init__(self, code, retryable=False):
        self.code, self.retryable = code, retryable
        super().__init__(code)


def aws_error(exc):
    code = exc.response.get("Error", {}).get("Code", "aws_error") if isinstance(exc, ClientError) else "aws_transport_error"
    transient = code in {"ThrottlingException", "Throttling", "TooManyRequestsException", "ServiceUnavailableException",
                         "InternalFailure", "InternalServerException", "aws_transport_error", "SlowDown"}
    return ProviderError(code, transient)


def validate_wav(data, record, settings):
    if len(data) != record["byte_length"] or len(data) > settings.max_audio_bytes:
        raise ProviderError("audio_size_mismatch", True)
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ProviderError("audio_checksum_mismatch", True)
    try:
        with wave.open(io.BytesIO(data), "rb") as audio:
            if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getframerate() not in (8000, 16000) or audio.getcomptype() != "NONE":
                raise ProviderError("unsupported_audio_format", True)
            frames = audio.getnframes()
            seconds = frames / audio.getframerate()
            if not 0 < seconds <= settings.max_audio_seconds:
                raise ProviderError("audio_duration_limit", True)
            if len(audio.readframes(frames)) != frames * 2:
                raise ProviderError("truncated_audio", True)
            return {"duration_seconds": seconds, "sample_rate": audio.getframerate()}
    except (wave.Error, EOFError):
        raise ProviderError("invalid_wav", True) from None


class FixtureProviders:
    """Explicitly fake services for local contract tests; never AWS verification."""
    name = "fixture-not-aws"

    def __init__(self, settings):
        self.settings = settings
        self.root = settings.runtime_dir / "objects"
        self.root.mkdir(parents=True, exist_ok=True)
        self.calls = 0
        self.raw_override = None
        self.error = None

    def analyze(self, request, shelters):
        self.calls += 1
        if self.error:
            raise self.error
        numbers = re.findall(r"\b\d+\b", request["original_text"])
        q = int(numbers[0]) if numbers else None
        text = request["original_text"].lower()
        if q is None:
            q = next((v for k, v in NUMBER_WORDS.items() if re.search(r"\b" + k + r"\b", text) and v > 0), None)
        item = "blankets" if "blanket" in text else "food_packs" if "food" in text else "water_packs" if "water" in text else "other"
        raw = self.raw_override or json.dumps({"item_id": item, "quantity": q, "unit": "piece" if item == "blankets" else "pack",
                                              "shelter_id": request["destination_shelter_id"], "negated": False,
                                              "missing_fields": [] if q else ["quantity"], "summary": "Synthetic fixture proposal; no AWS inference occurred."})
        return raw, {"provider": self.name, "model_id": "fixture", "request_id": None, "usage": {}}

    def upload_authorization(self, record):
        return {"method": "PUT", "url": self.settings.public_base_url + "/v1/local-uploads/" + record["transcription_id"],
                "fields": {}, "headers": {"Content-Type": "audio/wav"}, "requires_bearer_token": True,
                "expires_in_seconds": self.settings.upload_ttl_seconds}

    def write_upload(self, record, data):
        (self.root / (record["transcription_id"] + ".wav")).write_bytes(data)

    def seal_upload(self, record):
        path = self.root / (record["transcription_id"] + ".wav")
        if not path.exists():
            raise ProviderError("upload_missing", True)
        data = path.read_bytes()
        metadata = validate_wav(data, record, self.settings)
        (self.root / (record["transcription_id"] + ".sealed.wav")).write_bytes(data)
        return metadata

    def start_transcription(self, record):
        return {"provider": self.name, "job_name": "fixture-" + record["transcription_id"], "request_id": None}

    def poll_transcription(self, record):
        return {"status": "completed", "transcript": "Shelter A needs 2 water packs.", "provider": self.name,
                "request_id": None, "job_name": "fixture-" + record["transcription_id"]}


class AWSProviders:
    name = "aws"

    def __init__(self, settings, session):
        self.settings = settings
        cfg = Config(region_name=settings.aws_region, connect_timeout=5, read_timeout=45,
                     retries={"total_max_attempts": 1, "mode": "standard"})
        self.bedrock = session.client("bedrock-runtime", config=cfg)
        self.s3 = session.client("s3", config=cfg)
        self.transcribe = session.client("transcribe", config=cfg)
        self.lambda_client = session.client("lambda", config=Config(connect_timeout=3, read_timeout=5,
                                                                   retries={"total_max_attempts": 1})) if settings.worker_function_name else None

    def wake_worker(self, kind, identifier):
        if not self.lambda_client:
            return
        self.allowed()
        try:
            self.lambda_client.invoke(FunctionName=self.settings.worker_function_name, InvocationType="Event",
                                      Payload=json.dumps({"task_key": kind + "#" + str(identifier)}).encode())
        except (ClientError, BotoCoreError) as exc:
            raise aws_error(exc) from None

    def allowed(self):
        if not self.settings.allow_aws_writes_and_ai:
            raise ProviderError("aws_activity_not_approved")

    def analyze(self, request, shelters):
        self.allowed()
        started = time.monotonic()
        try:
            result = self.bedrock.converse(modelId=self.settings.model_id,
                                          system=[{"text": SYSTEM_PROMPT + " Use extract_request to return these fields. The tool only reports data; it performs no action."}],
                                          toolConfig=extraction_tool(),
                                          messages=prompt(request, shelters),
                                          inferenceConfig={"maxTokens": 640, "temperature": 0})
        except (ClientError, BotoCoreError) as exc:
            raise aws_error(exc) from None
        text = structured_output(result)
        return text, {"provider": self.name, "model_id": self.settings.model_id,
                      "request_id": result.get("ResponseMetadata", {}).get("RequestId"),
                      "model_ms": round((time.monotonic() - started) * 1000),
                      "usage": result.get("usage", {}), "stop_reason": result.get("stopReason")}

    def upload_key(self, record):
        return self.settings.object_prefix + "uploads/" + record["transcription_id"] + ".wav"

    def sealed_key(self, record):
        return self.settings.object_prefix + "sealed/" + record["transcription_id"] + ".wav"

    def output_key(self, record):
        return self.settings.object_prefix + "transcripts/" + record["transcription_id"] + ".json"

    def upload_authorization(self, record):
        self.allowed()
        fields = {"Content-Type": "audio/wav", "x-amz-server-side-encryption": "AES256"}
        conditions = [{k: v} for k, v in fields.items()] + [["content-length-range", record["byte_length"], record["byte_length"]]]
        result = self.s3.generate_presigned_post(Bucket=self.settings.bucket_name, Key=self.upload_key(record),
                                                 Fields=fields, Conditions=conditions,
                                                 ExpiresIn=self.settings.upload_ttl_seconds)
        return {"method": "POST", "url": result["url"], "fields": result["fields"], "headers": {},
                "requires_bearer_token": False, "expires_in_seconds": self.settings.upload_ttl_seconds}

    def seal_upload(self, record):
        self.allowed()
        try:
            response = self.s3.get_object(Bucket=self.settings.bucket_name, Key=self.upload_key(record))
            try:
                if response["ContentLength"] > self.settings.max_audio_bytes:
                    raise ProviderError("audio_size_limit", True)
                data = response["Body"].read(self.settings.max_audio_bytes + 1)
            finally:
                response["Body"].close()
            metadata = validate_wav(data, record, self.settings)
            # A separate key is never presigned for the client. Reusing its short-lived
            # upload grant cannot change the bytes used by a running transcription.
            try:
                self.s3.put_object(Bucket=self.settings.bucket_name, Key=self.sealed_key(record), Body=data,
                                   ContentType="audio/wav", ServerSideEncryption="AES256", IfNoneMatch="*",
                                   Metadata={"sha256": record["sha256"]})
            except ClientError as exc:
                if exc.response["Error"]["Code"] not in {"PreconditionFailed", "412"}:
                    raise
                existing = self.s3.head_object(Bucket=self.settings.bucket_name, Key=self.sealed_key(record))
                if existing.get("Metadata", {}).get("sha256") != record["sha256"]:
                    raise ProviderError("sealed_audio_conflict")
            return metadata
        except ProviderError:
            raise
        except (ClientError, BotoCoreError) as exc:
            if isinstance(exc, ClientError) and exc.response["Error"]["Code"] in {"NoSuchKey", "404"}:
                raise ProviderError("upload_missing", True) from None
            raise aws_error(exc) from None

    def start_transcription(self, record):
        self.allowed()
        name = "relay-mvp-" + record["transcription_id"]
        uri = "s3://" + self.settings.bucket_name + "/" + self.sealed_key(record)
        try:
            response = self.transcribe.start_transcription_job(
                TranscriptionJobName=name, LanguageCode=record["language_code"], MediaFormat="wav",
                Media={"MediaFileUri": uri}, OutputBucketName=self.settings.bucket_name,
                OutputKey=self.output_key(record))
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ConflictException":
                raise aws_error(exc) from None
            try:
                response = self.transcribe.get_transcription_job(TranscriptionJobName=name)
                job = response["TranscriptionJob"]
                if job.get("Media", {}).get("MediaFileUri") != uri or job.get("LanguageCode") != record["language_code"]:
                    raise ProviderError("transcription_job_conflict")
            except (ClientError, BotoCoreError) as get_exc:
                raise aws_error(get_exc) from None
        except BotoCoreError as exc:
            raise aws_error(exc) from None
        return {"provider": self.name, "job_name": name,
                "request_id": response.get("ResponseMetadata", {}).get("RequestId")}

    def poll_transcription(self, record):
        self.allowed()
        name = "relay-mvp-" + record["transcription_id"]
        try:
            response = self.transcribe.get_transcription_job(TranscriptionJobName=name)
            job = response["TranscriptionJob"]
            result = {"provider": self.name, "job_name": name,
                      "request_id": response.get("ResponseMetadata", {}).get("RequestId")}
            if job["TranscriptionJobStatus"] == "FAILED":
                raise ProviderError("transcription_service_failed")
            if job["TranscriptionJobStatus"] != "COMPLETED":
                return {**result, "status": "processing"}
            response = self.s3.get_object(Bucket=self.settings.bucket_name, Key=self.output_key(record))
            try:
                data = response["Body"].read(1_000_001)
            finally:
                response["Body"].close()
            if len(data) > 1_000_000:
                raise ProviderError("transcript_output_limit")
            transcript = json.loads(data)["results"]["transcripts"][0]["transcript"]
            if not isinstance(transcript, str) or len(transcript) > 4096:
                raise ProviderError("transcript_text_limit")
            return {**result, "status": "completed", "transcript": transcript}
        except ProviderError:
            raise
        except (ClientError, BotoCoreError) as exc:
            raise aws_error(exc) from None
        except (ValueError, KeyError, IndexError, TypeError):
            raise ProviderError("invalid_transcript_output") from None
