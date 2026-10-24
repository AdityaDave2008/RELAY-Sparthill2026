import importlib.util
import json
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from relay_backend.api import build_service, create_app
from relay_backend.config import Settings

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).resolve().parents[1] / "scripts/bootstrap_local.py")
bootstrap_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap_module)


class PrivateTestEnvironment(dict):
    def __repr__(self):
        return "<local test environment; token values redacted>"


@pytest.fixture
def env(tmp_path):
    config, tokens = bootstrap_module.bootstrap(tmp_path)
    settings = Settings.load(config)
    service = build_service(settings)
    client = TestClient(create_app(settings, service))
    return PrivateTestEnvironment(settings=settings, service=service, client=client,
                                  tokens=json.loads(tokens.read_text()), config=config)


def auth(env, name="test-requester-a"):
    return {"Authorization": "Bearer " + env["tokens"][name]}
