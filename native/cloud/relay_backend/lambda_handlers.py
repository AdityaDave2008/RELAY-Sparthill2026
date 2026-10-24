"""Optional hosting entrypoints. Deployment is separate from local AWS tests."""
import json
import os
import time
from functools import lru_cache

from mangum import Mangum

from .api import build_service, create_app
from .config import Settings
from .service import Worker


@lru_cache(maxsize=1)
def runtime():
    data = json.loads(os.environ["RELAY_SETTINGS_JSON"])
    data.update(runtime_dir="/tmp/relay", aws_profile=None)
    data["worker_function_name"] = os.environ.get("RELAY_WORKER_FUNCTION")
    settings = Settings.model_validate(data)
    service = build_service(settings)
    return Mangum(create_app(settings, service), lifespan="off"), Worker(service)


def api(event, context):
    return runtime()[0](event, context)


def worker(event, context):
    processor = runtime()[1]
    # Durable work is authoritative; event carries only an optional lookup hint.
    target = event.get("task_key")
    if target and (not isinstance(target, str) or not target.startswith(("request#", "transcription#", "interpretation#"))):
        target = None
    deadline = time.monotonic() + 25
    count = 0
    while time.monotonic() < deadline and context.get_remaining_time_in_millis() > 55000:
        worked = processor.run_once(target)
        target = None
        count += int(worked)
        if not worked:
            time.sleep(1)
    return {"processed_operations": count}
