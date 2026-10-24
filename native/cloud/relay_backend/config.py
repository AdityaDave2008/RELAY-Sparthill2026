import json
import os
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Membership(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["requester", "dispatcher"]
    incident_id: str
    shelter_ids: list[str]


class Shelter(BaseModel):
    shelter_id: str
    incident_id: str
    display_name: str


class Settings(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: Literal["local-test", "aws"] = "local-test"
    storage: Literal["sqlite", "dynamodb"] = "sqlite"
    runtime_dir: Path
    public_base_url: str = "http://127.0.0.1:8787"
    issuer: str = "http://relay.local-test"
    client_id: str = "relay-local-test"
    local_public_key: Path | None = None
    aws_region: Literal["us-east-1"] = "us-east-1"
    expected_account: str = "928489693154"
    aws_profile: str | None = "relay-workshop"
    aws_credentials_file: Path | None = None
    aws_config_file: Path | None = None
    aws_login_cache_directory: Path | None = None
    worker_function_name: str | None = None
    accelerate_previews: bool = False
    table_name: str = "relay-messages"
    bucket_name: str = "relay-artifacts-928489693154-use1"
    object_prefix: str = "cloud-mvp-v1/"
    model_id: str = "amazon.nova-lite-v1:0"
    allow_aws_writes_and_ai: bool = False
    max_attempts: int = Field(default=3, ge=1, le=5)
    max_requests: int = Field(default=100, ge=1, le=1000)
    max_transcriptions: int = Field(default=5, ge=1, le=100)
    lease_seconds: int = Field(default=120, ge=60, le=600)
    upload_ttl_seconds: int = Field(default=300, ge=60, le=900)
    max_live_streams: int = Field(default=4, ge=1, le=8)
    max_audio_bytes: int = 2_097_152
    max_audio_seconds: int = 60
    transcription_timeout_seconds: int = 900
    memberships: dict[str, Membership]
    shelters: list[Shelter]

    @model_validator(mode="after")
    def valid_mode(self):
        self.runtime_dir = self.runtime_dir.expanduser().resolve()
        if self.mode == "aws":
            if self.local_public_key is not None or not self.issuer.startswith("https://cognito-idp.us-east-1.amazonaws.com/"):
                raise ValueError("AWS mode requires a real Cognito issuer and forbids test signing keys")
            if not self.client_id or self.client_id == "relay-local-test":
                raise ValueError("Configure the verified Cognito public app client")
        elif self.storage != "sqlite" or not self.local_public_key:
            raise ValueError("Local-test mode requires SQLite and a test public key")
        if not self.object_prefix.startswith("cloud-mvp-v1/") or ".." in self.object_prefix:
            raise ValueError("Use the isolated cloud-mvp-v1/ object namespace")
        if self.max_audio_bytes > 2_097_152 or self.max_audio_seconds > 60:
            raise ValueError("This milestone caps WAV recordings at 2 MiB and 60 seconds")
        return self

    @classmethod
    def load(cls, path: str | Path):
        return cls.model_validate_json(Path(path).read_text())

    def aws_session(self):
        import boto3
        if self.aws_credentials_file:
            os.environ["AWS_SHARED_CREDENTIALS_FILE"] = str(self.aws_credentials_file)
        if self.aws_config_file:
            os.environ["AWS_CONFIG_FILE"] = str(self.aws_config_file)
        if self.aws_login_cache_directory:
            os.environ["AWS_LOGIN_CACHE_DIRECTORY"] = str(self.aws_login_cache_directory)
        return boto3.Session(profile_name=self.aws_profile, region_name=self.aws_region)

    def safe_client_config(self):
        return {"api_base_url": self.public_base_url, "issuer": self.issuer,
                "client_id": self.client_id, "region": self.aws_region,
                "schema_version": 1, "hosting_mode": self.mode}
