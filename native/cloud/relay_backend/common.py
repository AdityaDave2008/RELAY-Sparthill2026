"""Shared durable-key and error contracts; no providers or credentials."""
import hashlib
import json

PREFIX = "RELAY_MVP_V1#"
WORK = PREFIX + "WORK"


def key(kind, identifier):
    return PREFIX + kind.upper() + "#" + str(identifier), "META"


def work_key(kind, identifier):
    return WORK, kind + "#" + str(identifier)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


class APIError(Exception):
    def __init__(self, status, code, message, retryable=False):
        self.status, self.code, self.message, self.retryable = status, code, message, retryable
        super().__init__(code)
