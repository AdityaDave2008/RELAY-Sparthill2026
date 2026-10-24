import argparse
import time

import uvicorn

from .api import build_service, create_app
from .config import Settings
from .service import Worker


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["serve", "worker"])
    parser.add_argument("--config", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    settings = Settings.load(args.config)
    if settings.mode == "local-test" and args.host not in {"127.0.0.1", "::1", "localhost"}:
        raise SystemExit("Local-test authentication is restricted to loopback.")
    service = build_service(settings)
    if args.command == "serve":
        uvicorn.run(create_app(settings, service), host=args.host, port=args.port, access_log=False, ws_max_size=16384, ws_max_queue=4)
    else:
        worker = Worker(service)
        while True:
            try:
                worked = worker.run_once()
            except KeyboardInterrupt:
                break
            except Exception as exc:
                # Do not log tokens, AWS credentials, presigned URLs, or request/audio contents.
                print("Worker operation interrupted:", type(exc).__name__, flush=True)
                worked = False
            if args.once:
                break
            time.sleep(0.1 if worked else 0.5)


if __name__ == "__main__":
    main()
