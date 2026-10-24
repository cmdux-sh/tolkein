"""Collect CodexBar usage and publish one snapshot."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from tolkeins.codexbar import CollectorAbort, fetch_provider
from tolkeins.config import ConfigError, CollectorConfig, load_config
from tolkeins.normalize import SubscriptionError, build_snapshot, load_subscriptions
from tolkeins.publish import PublishError, post_snapshot


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Publish AI subscription usage from CodexBar.")
    parser.add_argument("--config-dir", help="Directory with config.env and subscriptions.yaml")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the snapshot as JSON and do not contact the Worker",
    )
    args = parser.parse_args(argv)
    try:
        config = load_config(None if args.config_dir is None else Path(args.config_dir))
        snapshot = collect(config)
    except (ConfigError, SubscriptionError, CollectorAbort) as error:
        print(str(error), file=sys.stderr)
        return 2 if isinstance(error, (ConfigError, SubscriptionError)) else 1
    if args.dry_run:
        json.dump(snapshot, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if not config.worker_url or not config.write_token:
        print("WORKER_URL and WRITE_TOKEN are required in config.env", file=sys.stderr)
        return 2
    try:
        post_snapshot(config.worker_url, config.write_token, snapshot)
    except PublishError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"posted {snapshot['generatedAt']}", file=sys.stderr)
    return 0


def collect(config: CollectorConfig) -> dict[str, Any]:
    subscriptions = {}
    if config.subscriptions_path.exists():
        subscriptions = load_subscriptions(config.subscriptions_path.read_text(encoding="utf-8"))
    payloads: dict[str, Any] = {}
    for provider in config.providers:
        payloads[provider] = fetch_provider(config.codexbar_bin, provider, config.timeout_seconds)
        record = payloads[provider]
        status = "ok"
        if isinstance(record, list) and record and isinstance(record[0], dict) and record[0].get("error"):
            status = "error"
        elif isinstance(record, dict) and record.get("error"):
            status = "error"
        print(f"{provider} {status}", file=sys.stderr)
    generated_at = datetime.now(timezone.utc)
    return build_snapshot(payloads, subscriptions, config.providers, generated_at)


if __name__ == "__main__":
    raise SystemExit(main())
